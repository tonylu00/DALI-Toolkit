import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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

  String _resolveCaller() {
    // Skip first few frames that are inside logging utility itself
    final stack = StackTrace.current.toString().split('\n');
    for (final line in stack) {
      if (line.isEmpty) continue;
      // Exclude lines belonging to this file/class
      if (line.contains('DaliLog.') || line.contains('log.dart')) {
        continue;
      }
      // Try to extract the function name pattern 'package:... (FUNCTION (file:line:col))'
      final match = RegExp(r'(#\d+\s+)?(?:.+?\()?(\w+)(?:\.<anonymous>)?\s*\(').firstMatch(line);
      if (match != null) {
        return match.group(2) ?? 'unknown';
      }
      // Fallback: trim
      return line.trim();
    }
    return 'unknown';
  }

  void _log(LogLevel level, String message) {
    assert(() {
      final caller = _resolveCaller();
      final ts = DateTime.now().toIso8601String();
      final formatted = '[${level.name.toUpperCase()}][$caller][$ts] $message';
      addLog(formatted, raw: true);
      return true;
    }());
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
  }
}
