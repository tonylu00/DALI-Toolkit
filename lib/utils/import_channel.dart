import 'dart:async';
import 'package:flutter/services.dart';

class ImportChannel {
  ImportChannel._();
  static final ImportChannel instance = ImportChannel._();

  final _controller = StreamController<String>.broadcast();
  Stream<String> get stream => _controller.stream;

  bool _inited = false;
  static const _channelName = 'org.tonycloud.dalimaster/import';
  late final MethodChannel _channel;

  void init() {
    if (_inited) return;
    _inited = true;
    _channel = const MethodChannel(_channelName);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'importProjectJson') {
        final arg = call.arguments;
        if (arg is String && arg.isNotEmpty) {
          _controller.add(arg);
        }
      }
    });
  }

  // For platforms that can deliver JSON from Dart side directly
  void deliverJson(String json) {
    if (json.isNotEmpty) {
      _controller.add(json);
    }
  }
}
