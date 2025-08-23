import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'connection.dart';

class _UnsupportedConnection implements Connection {
  @override
  String connectedDeviceId = '';
  @override
  String get type => 'Serial Unsupported';
  @override
  Uint8List? readBuffer;

  @override
  Future<void> connect(String address, {int port = 0}) async =>
      throw UnsupportedError('Serial not supported on this platform');
  @override
  Future<void> send(Uint8List data) async =>
      throw UnsupportedError('Serial not supported on this platform');
  @override
  Future<Uint8List?> read(int length, {int timeout = 200}) async => null;
  @override
  void onReceived(void Function(Uint8List data) onData) {}
  @override
  void disconnect() {}
  @override
  Future<void> startScan() async {}
  @override
  void stopScan() {}
  @override
  bool isDeviceConnected() => false;
  @override
  void openDeviceSelection(BuildContext context) {}
  @override
  void renameDeviceDialog(BuildContext context, String currentName) {}
}

Connection createSerialConnectionImpl() => _UnsupportedConnection();

bool isSerialSupportedImpl() => false;
