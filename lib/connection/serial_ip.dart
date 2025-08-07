import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'connection.dart';

class TcpClient implements Connection {
  late Socket _socket;
  final Completer<void> _doneCompleter = Completer<void>();
  bool _isConnected = false;

  @override
  String connectedDeviceId = '';

  @override
  final String type = 'TCP/IP';

  @override
  Uint8List? readBuffer;

  @override
  Future<void> connect(String address, {int port = 12345}) async {
    _socket = await Socket.connect(address, port);
    _isConnected = true;
    _socket.done.then((_) {
      _isConnected = false;
      _doneCompleter.complete();
    });
    debugPrint('Connected to: ${_socket.remoteAddress.address}:${_socket.remotePort}');
  }

  @override
  Future<void> send(Uint8List data) async {
    _socket.add(data);
  }

  @override
  Future<Uint8List?> read(int len, {int timeout = 100}) async {
    throw UnimplementedError();
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _socket.listen((data) {
      onData(Uint8List.fromList(data));
    });
  }

  @override
  void disconnect() {
    if (_isConnected) {
      _isConnected = false;
      _socket.close();
    }
  }

  @override
  Future<void> startScan() async {
    throw UnimplementedError();
  }

  @override
  void stopScan() {
    throw UnimplementedError();
  }

  @override
  bool isDeviceConnected() {
    return _isConnected;
  }

  @override
  void showDevicesDialog(BuildContext context) {
    throw UnimplementedError();
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    throw UnimplementedError();
  }
}
