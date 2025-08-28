import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LogLevel { debug, info, warning, error }

class DaliLog {
  static DaliLog? _instance;

  static DaliLog get instance {
    _instance ??= DaliLog();
    return _instance!;
  }

  final List<String> _logMessages = [];
  final StreamController<List<String>> _logStreamController =
      StreamController<List<String>>.broadcast();

  static const String _kLogLevelKey = 'logLevel';
  LogLevel _currentLevel = LogLevel.info; // default until init
  final StreamController<LogLevel> _levelController = StreamController<LogLevel>.broadcast();

  // Initialize log level from SharedPreferences; set default on first launch
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kLogLevelKey)) {
      // Default: debug in debug mode, info in release/profile
      _currentLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
      await prefs.setInt(_kLogLevelKey, _currentLevel.index);
    } else {
      final idx = prefs.getInt(_kLogLevelKey) ?? LogLevel.info.index;
      _currentLevel = LogLevel.values[idx.clamp(0, LogLevel.values.length - 1)];
    }
    _levelController.add(_currentLevel);
  }

  LogLevel get currentLevel => _currentLevel;

  Future<void> setLevel(LogLevel level) async {
    _currentLevel = level;
    _levelController.add(level);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLogLevelKey, level.index);
  }

  Stream<LogLevel> get levelStream => _levelController.stream;

  String _resolveCaller() {
    // Try to find the first non-logger frame and extract a concise symbol.
    final lines = StackTrace.current.toString().split('\n');
    final ignoreTokens = <String>[
      'DaliLog.',
      '/dali/log.dart',
      ' log.dart', // space to avoid matching arbitrary paths ending with log.dart as a method
      'core_patch.dart', // Flutter Web: StackTrace.current getter
      'get current',
      'StackTrace.current',
      'package:stack_trace',
      'stack_trace.dart',
      // Common async/runtime frames to ignore on Web
      'async_patch.dart',
      'zone.dart',
      'future_impl.dart',
      'js_helper.dart',
    ];

    String? fallback; // file.dart:line as a weak fallback

    for (final raw in lines) {
      if (raw.isEmpty) continue;
      final line = raw.trim();

      // Skip frames from the logger or internal stack machinery
      if (ignoreTokens.any((t) => line.contains(t))) {
        continue;
      }

      String? symbol;

      // 1) Dart VM / Flutter mobile format: '#1      Class.method (package:...)'
      final mVm = RegExp(r'#\d+\s+([^\s(]+)').firstMatch(line);
      if (mVm != null) {
        symbol = mVm.group(1);
      }

      // 2) Flutter Web (dev compiler) format:
      //    'package:foo/bar.dart 10:2  Class.method' or 'packages/foo/bar.dart 10:2  function'
      if (symbol == null) {
        final mDevc = RegExp(r'^[^\s]+\.dart\s+\d+:\d+\s+(.+)$').firstMatch(line);
        if (mDevc != null) {
          symbol = mDevc.group(1);
        }
      }

      // 3) JS style (dart2js): 'at Class.method (main.dart.js:...)' or 'at Object.method (...)'
      if (symbol == null) {
        final mJs = RegExp(r'^at\s+([^\s(]+)').firstMatch(line);
        if (mJs != null) {
          symbol = mJs.group(1);
        }
      }

      if (symbol != null) {
        // Normalize anonymous closures and noisy prefixes
        symbol = symbol
            .replaceAll('<anonymous closure>', 'anon')
            .replaceAll('<anonymous-closure>', 'anon')
            .replaceAll('Object.', '')
            .replaceAll('new ', '')
            .replaceAll('\n', '')
            .replaceAll('\t', '')
            .trim();

        // Skip uninformative Web symbols like <fn> or pure anonymous markers
        if (symbol == '<fn>' || symbol == 'anon' || RegExp(r'^<[^>]+>$').hasMatch(symbol)) {
          // keep scanning for a better frame; fallback will be file.dart:line
          continue;
        }

        // Skip common async runtime symbols (Web/devc)
        const skipSymbols = <String>{
          'runUnary',
          'runGuarded',
          '_rootRun',
          '_rootRunUnary',
          '_microtaskLoop',
          '_startMicrotaskLoop',
          '_Future',
          '_then',
          '_completeWithValue',
          '_propagateToListeners',
          'newFuture',
          '_asyncThenWrapperHelper',
          '_asyncCatchHelper',
        };
        if (skipSymbols.contains(symbol) ||
            symbol.startsWith('_rootRun') ||
            symbol.startsWith('_microtaskLoop')) {
          continue;
        }

        // Reduce very long dot-paths to the last two segments (Class.method)
        if (symbol.contains('.')) {
          final parts = symbol.split('.');
          if (parts.length >= 2) {
            symbol = '${parts[parts.length - 2]}.${parts.last}';
          }
        }

        // Avoid returning logger frames accidentally
        if (symbol.contains('DaliLog') || symbol.contains(' log')) {
          continue;
        }

        // If symbol is still a bare function name without dot and we have a file:line fallback,
        // prefer the fallback for better locality context on Web.
        if (!symbol.contains('.') && fallback != null) {
          return fallback;
        }
        return symbol;
      }

      // Prepare a lightweight fallback like 'file.dart:line' in case we never find a symbol
      fallback ??= () {
        final mf = RegExp(r'([A-Za-z0-9_\-/]+\.dart)\s+(\d+):\d+').firstMatch(line);
        if (mf != null) {
          return '${mf.group(1)}:${mf.group(2)}';
        }
        return null;
      }();
    }
    return fallback ?? 'unknown';
  }

  void _log(LogLevel level, String message) {
    // Filter by current level threshold
    if (level.index < _currentLevel.index) return;
    final caller = _resolveCaller();
    final ts = DateTime.now().toIso8601String();
    final formatted = '[${level.name.toUpperCase()}][$caller][$ts] $message';
    addLog(formatted, raw: true);
  }

  // raw=true means the message is already formatted (internal use in debug mode)
  void addLog(String message, {bool raw = false}) {
    // Only append in debug (assert section already ensured) or when raw is forced from _log
    _logMessages.add(message);
    _logStreamController.add(List.unmodifiable(_logMessages));
    debugPrint(message);
  }

  // Public helpers
  /// Debug-only log. In release/profile builds this is stripped by the compiler.
  /// Note: the message is still evaluated at call-site. For expensive messages,
  /// prefer [debugLogLazy].
  void debugLog(String message) {
    assert(() {
      _log(LogLevel.debug, message);
      return true;
    }());
  }

  /// Debug-only log with lazy message builder. The builder is only executed
  /// in debug mode; in release/profile the entire block is removed.
  void debugLogLazy(Object Function() messageBuilder) {
    assert(() {
      _log(LogLevel.debug, messageBuilder().toString());
      return true;
    }());
  }

  void infoLog(String message) => _log(LogLevel.info, message);
  void warningLog(String message) => _log(LogLevel.warning, message);
  void errorLog(String message) => _log(LogLevel.error, message);

  List<String> get logMessages => List.unmodifiable(_logMessages);

  void clearLogs() {
    _logMessages.clear();
    _logStreamController.add(List.unmodifiable(_logMessages));
  }

  Stream<List<String>> get logStream => _logStreamController.stream;

  ListView listBuilder(List<String> list, {ScrollController? controller}) {
    return ListView.builder(
      controller: controller,
      itemCount: list.length,
      itemBuilder: (context, index) {
        return Text(list[index], style: const TextStyle(fontSize: 10));
      },
    );
  }

  void showLogDialog(BuildContext context, String title, {bool clear = true, onCanceled}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _LogDialogContent(title: title);
      },
    );
  }

  void dispose() {
    _logStreamController.close();
    _levelController.close();
  }
}

class _LogDialogContent extends StatefulWidget {
  final String title;
  const _LogDialogContent({required this.title});

  @override
  State<_LogDialogContent> createState() => _LogDialogContentState();
}

class _LogDialogContentState extends State<_LogDialogContent> {
  late final ScrollController _controller;
  bool _autoScrollEnabled = true; // user toggle, default on
  bool _atBottom = true; // tracking whether the list is at/near bottom

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    // If user is near the bottom, enable auto-scroll; otherwise disable
    final threshold = 16.0;
    final atBottom = pos.pixels >= (pos.maxScrollExtent - threshold);
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
      });
    }
  }

  void _maybeAutoScroll() {
    if (!_autoScrollEnabled || !_controller.hasClients || !_atBottom) return;
    // Schedule after the current frame so the list has correct extent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final target = _controller.position.maxScrollExtent;
      // Use jumpTo to guarantee keeping up with fast incoming logs
      try {
        _controller.jumpTo(target);
      } catch (_) {
        // In case of out-of-range during rapid rebuilds, clamp safely
        final pos = _controller.position;
        final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        _controller.jumpTo(clamped);
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = DaliLog.instance;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('log.auto_scroll').tr(),
                Switch(
                  value: _autoScrollEnabled,
                  onChanged: (v) {
                    setState(() => _autoScrollEnabled = v);
                    if (v) _maybeAutoScroll();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: StreamBuilder<List<String>>(
                stream: log.logStream,
                builder: (context, snapshot) {
                  List<String> items;
                  if (log._logMessages.isNotEmpty) {
                    items = log._logMessages;
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text('log.no_logs').tr());
                  } else {
                    items = snapshot.data!;
                  }

                  // Try autoscroll when new data comes in
                  _maybeAutoScroll();

                  return log.listBuilder(items, controller: _controller);
                },
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            log.clearLogs();
            Navigator.of(context).pop();
          },
          child: const Text('common.clear').tr(),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('common.close').tr(),
        ),
      ],
    );
  }
}
