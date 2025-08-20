import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class DaliLog {
  static DaliLog? _instance;

  static DaliLog get instance {
    _instance ??= DaliLog();
    return _instance!;
  }

  final List<String> _logMessages = [];
  final StreamController<List<String>> _logStreamController =
      StreamController<List<String>>.broadcast();

  void addLog(String message) {
    _logMessages.add(message);
    _logStreamController.add(List.unmodifiable(_logMessages));
    debugPrint(message);
  }

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
