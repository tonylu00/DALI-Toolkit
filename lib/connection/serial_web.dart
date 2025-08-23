import 'dart:async';
import 'dart:typed_data';
import 'dart:html';
import 'dart:js_util';
import 'package:flutter/material.dart';
import 'package:dalimaster/dali/log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'manager.dart';
import 'connection.dart';

class SerialWebManager implements Connection {
  dynamic _port;
  dynamic _reader;
  @override
  Uint8List? readBuffer;
  void Function(Uint8List data)? _onDataReceived;
  @override
  String connectedDeviceId = "";
  @override
  final String type = 'Serial Web';
  bool _isListening = false;

  // JS interop helpers
  Future<dynamic> _requestPort() async {
    try {
      final serial = getProperty(window.navigator, 'serial');
      return await promiseToFuture(callMethod(serial, 'requestPort', []));
    } catch (e) {
      if (e is DomException && e.name == 'NotFoundError') {
        DaliLog.instance.debugLog('Serial port selection cancelled by user');
        return null;
      }
      DaliLog.instance.debugLog('Error requesting serial port: $e');
      return null;
    }
  }

  Future<bool> _openPort(dynamic port, int baudRate, {bool isRetry = false}) async {
    try {
      await promiseToFuture(callMethod(port, 'open', [
        jsify({'baudRate': baudRate})
      ]));
      return true;
    } catch (e) {
      if (e is DomException && e.name == 'InvalidStateError') {
        DaliLog.instance.debugLog('Serial port is already open, try using current instance');
        await _closePort(port);
        if (!isRetry) {
          return _openPort(port, baudRate, isRetry: true);
        }
        if (isRetry) {
          DaliLog.instance.debugLog('Retrying to open serial port failed: $e');
          return false;
        }
      }
      DaliLog.instance.debugLog('Error opening serial port: $e');
      return false;
    }
  }

  Future<bool> _cancelPort() async {
    _isListening = false;
    if (_reader != null) {
      await promiseToFuture(callMethod(_reader, 'cancel', []));
    }
    return true;
  }

  Future<bool> _closePort(dynamic port) async {
    try {
      await _cancelPort();
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    } catch (e) {
      DaliLog.instance.debugLog('Error closing serial port: $e');
      return false;
    }
  }

  Future<bool> _writePort(dynamic port, Uint8List data) async {
    try {
      final writable = getProperty(port, 'writable');
      final writer = callMethod(writable, 'getWriter', []);
      await promiseToFuture(callMethod(writer, 'write', [data]));
      callMethod(writer, 'releaseLock', []);
      return true;
    } catch (e) {
      DaliLog.instance.debugLog('Serial Web send error: $e');
      return false;
    }
  }

  void _listenPort(dynamic port, void Function(Uint8List data)? onData) async {
    if (port == null) return;
    _isListening = true;
    while (getProperty(port, 'readable') != null && _isListening) {
      final readable = getProperty(port, 'readable');
      _reader = callMethod(readable, 'getReader', []);
      try {
        while (true) {
          final result = await promiseToFuture(callMethod(_reader, 'read', []));
          if (result == null) break;
          final done = getProperty(result, 'done');
          if (done == true) {
            DaliLog.instance.debugLog('Serial Web read done');
            break;
          }
          final value = getProperty(result, 'value');
          if (value != null) {
            Uint8List data;
            if (value is ByteBuffer) {
              data = Uint8List.view(value);
            } else if (value is Uint8List) {
              data = value;
            } else if (value is List) {
              data = Uint8List.fromList(List<int>.from(value));
            } else {
              final buffer = getProperty(value, 'buffer');
              if (buffer is ByteBuffer) {
                data = Uint8List.view(buffer);
              } else {
                DaliLog.instance.debugLog(
                    'Serial Web recv: unknown value type: ' + value.runtimeType.toString());
                debugPrintStack();
                continue;
              }
            }
            readBuffer = data;
            onData?.call(data);
            DaliLog.instance.debugLog(
                'Serial Web recv: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          }
        }
      } catch (error) {
        DaliLog.instance.debugLog('Serial Web read error: $error');
      } finally {
        callMethod(_reader, 'releaseLock', []);
      }
    }
    await promiseToFuture(callMethod(port, 'close', []));
  }

  @override
  bool isDeviceConnected() => _port != null;

  @override
  Future<void> startScan() async {
    // Web Serial API 只能通过 requestPort 弹窗授权
    // 这里不做扫描，直接在 connect 时弹窗
  }

  @override
  void stopScan() {}

  @override
  Future<void> connect(String address, {int port = 0}) async {
    await disconnect();
    final portObj = await _requestPort();
    if (portObj == null) return;
    final opened = await _openPort(portObj, 9600);
    if (!opened) return;
    _port = portObj;
    connectedDeviceId = _port.hashCode.toString();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('serialPortId', connectedDeviceId);
    _listenPort(_port, _onDataReceived);
    ConnectionManager.instance.updateConnectionStatus(true);
    await Future.delayed(const Duration(milliseconds: 10));
    unawaited(ConnectionManager.instance.ensureGatewayType());
    DaliLog.instance.debugLog('Serial Web connected: $connectedDeviceId');
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_port == null) {
      DaliLog.instance.debugLog('Serial Web not connected');
      return;
    }
    await _writePort(_port, data);
    DaliLog.instance.debugLog(
        'Serial Web sent: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  @override
  Future<Uint8List?> read(int length, {int timeout = 200}) async {
    if (readBuffer != null && readBuffer!.isNotEmpty) {
      if (readBuffer!.length < length) {
        await Future.delayed(Duration(milliseconds: timeout));
        if (readBuffer == null || readBuffer!.length < length) {
          length = readBuffer!.length;
        }
      }
      final out = Uint8List.fromList(readBuffer!.sublist(0, length));
      final remain = readBuffer!.length - length;
      readBuffer = remain > 0 ? Uint8List.fromList(readBuffer!.sublist(length)) : null;
      return out;
    }
    return null;
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _onDataReceived = onData;
    _listenPort(_port, _onDataReceived);
  }

  @override
  Future<void> disconnect() async {
    dynamic result;
    if (_port != null) {
      result = await _closePort(_port);
    }
    if (result != null && result) {
      _port = null;
      connectedDeviceId = "";
      readBuffer = null;
      ConnectionManager.instance.updateConnectionStatus(false);
      DaliLog.instance.debugLog('Serial Web disconnected');
    } else {
      DaliLog.instance.debugLog('Serial Web disconnect failed');
    }
  }

  @override
  void openDeviceSelection(BuildContext context) {
    connect("request");
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('serial.rename_not_supported_web')));
  }

  Future<void> connectToSavedDevice() async {
    // Web Serial API 无法自动连接已授权设备
  }
}
