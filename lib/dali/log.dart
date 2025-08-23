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
    // Skip first few frames that are inside logging utility itself
    // Parse stack to find first frame outside logger, prefer "Class.method"
    final lines = StackTrace.current.toString().split('\n');
    for (var raw in lines) {
      if (raw.isEmpty) continue;
      final line = raw.trim();
      // Skip frames from logger itself
      if (line.contains('DaliLog.') ||
          line.contains('/dali/log.dart') ||
          line.contains('log.dart')) {
        continue;
      }
      // Common Dart VM format: '#1      Class.method (package:...)'
      final m1 = RegExp(r'#\d+\s+([^\s(]+)').firstMatch(line);
      String? symbol = m1?.group(1);

      // Fallback (e.g., JS/Web style): 'at Class.method (package:...)'
      symbol ??= RegExp(r'^at\s+([^\s(]+)').firstMatch(line)?.group(1);

      if (symbol != null) {
        // Normalize anonymous closure suffixes
        symbol = symbol
            .replaceAll('<anonymous closure>', 'anon')
            .replaceAll('<anonymous-closure>', 'anon');

        // If there are multiple dots, keep the last two segments as Class.method
        if (symbol.contains('.')) {
          final parts = symbol.split('.');
          if (parts.length >= 2) {
            symbol = '${parts[parts.length - 2]}.${parts.last}';
          }
        }
        return symbol;
      }

      // Last resort: return trimmed line
      return line;
    }
    return 'unknown';
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
  void debugLog(String message) => _log(LogLevel.debug, message);
  void infoLog(String message) => _log(LogLevel.info, message);
  void warningLog(String message) => _log(LogLevel.warning, message);
  void errorLog(String message) => _log(LogLevel.error, message);

  List<String> get logMessages => List.unmodifiable(_logMessages);

  void clearLogs() {
    _logMessages.clear();
    _logStreamController.add(List.unmodifiable(_logMessages));
  }

  Stream<List<String>> get logStream => _logStreamController.stream;

  ListView listBuilder(List<String> list) {
    return ListView.builder(
      itemCount: _logMessages.length,
      itemBuilder: (context, index) {
        return Text(_logMessages[index], style: const TextStyle(fontSize: 10));
      },
    );
  }

  void showLogDialog(BuildContext context, String title, {bool clear = true, onCanceled}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<String>>(
              stream: logStream,
              builder: (context, snapshot) {
                if (_logMessages.isNotEmpty) {
                  return listBuilder(_logMessages);
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('log.no_logs').tr());
                }
                return listBuilder(snapshot.data!);
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                clearLogs();
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
      },
    );
  }

  void dispose() {
    _logStreamController.close();
    _levelController.close();
  }
}
