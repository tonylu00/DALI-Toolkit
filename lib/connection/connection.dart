import 'dart:typed_data';

import 'package:flutter/material.dart';

abstract class Connection {
  Future<void> connect(String address, {int port});
  Future<void> send(Uint8List data);
  Future<Uint8List?> read(int length, {int timeout});
  void onReceived(void Function(Uint8List data) onData);
  void disconnect();
  Future<void> startScan();
  void stopScan();
  bool isDeviceConnected();
  void openDeviceSelection(BuildContext context);
  void renameDeviceDialog(BuildContext context, String currentName);
  Uint8List? readBuffer;
  String get connectedDeviceId;
  String get type;
}
