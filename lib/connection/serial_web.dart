// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:serial/serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'manager.dart';
import 'connection.dart';
import '/toast.dart';

class SerialWebManager implements Connection {
  SerialPort? _port;
  web.ReadableStreamDefaultReader? _reader;
  bool _keepReading = true;

  @override
  String connectedDeviceId = "";

  @override
  final String type = 'Serial Web';

  @override
  Uint8List? readBuffer;

  void Function(Uint8List data)? _onDataReceived;

  final List<SerialPort> _availablePorts = [];
  final _scanResultsController = StreamController<List<SerialPort>>.broadcast();
  Stream<List<SerialPort>> get scanResultsStream => _scanResultsController.stream;

  @override
  bool isDeviceConnected() {
    return _port != null && _port!.connected;
  }

  @override
  Future<void> startScan() async {
    try {
      _availablePorts.clear();
      // 获取已经授权的端口
      final portsPromise = web.window.navigator.serial.getPorts();
      final ports = await portsPromise.toDart;
      // 使用兼容的方式遍历数组
      for (var port in ports.toDart) {
        _availablePorts.add(port);
      }
      _scanResultsController.add(_availablePorts);
    } catch (e) {
      debugPrint('Error getting available ports: $e');
    }
  }

  @override
  void stopScan() {
    // Web Serial API 不需要显式停止扫描
  }

  @override
  Future<void> connect(String address, {int? port}) async {
    try {
      await disconnect();

      // 如果 address 是 "request"，则请求新端口
      SerialPort selectedPort;
      if (address == "request") {
        selectedPort = await web.window.navigator.serial.requestPort().toDart;
      } else {
        // 从可用端口中查找匹配的端口
        final portIndex = int.tryParse(address) ?? 0;
        if (portIndex < _availablePorts.length) {
          selectedPort = _availablePorts[portIndex];
        } else {
          debugPrint('Invalid port index: $address');
          return;
        }
      }

      await selectedPort.open(baudRate: 9600).toDart;

      _port = selectedPort;
      _keepReading = true;
      connectedDeviceId = selectedPort.getInfo().toString();

      ConnectionManager.instance.updateConnectionStatus(true);

      // 保存连接信息
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('serialPortId', connectedDeviceId);

      // 开始接收数据
      _startReceiving(selectedPort);

      debugPrint('Connected to serial port: $connectedDeviceId');
    } catch (e) {
      debugPrint('Error connecting to serial port: $e');
      ConnectionManager.instance.updateConnectionStatus(false);
    }
  }

  Future<void> _startReceiving(SerialPort port) async {
    while (port.readable != null && _keepReading) {
      final reader = port.readable!.getReader() as web.ReadableStreamDefaultReader;
      _reader = reader;

      while (_keepReading) {
        try {
          final result = await reader.read().toDart;

          if (result.done) {
            // Reader has been canceled
            break;
          }

          final value = result.value;
          if (value != null) {
            try {
              final data = value as JSUint8Array;
              final receivedData = data.toDart;
              readBuffer = receivedData;

              // 调用数据接收回调
              _onDataReceived?.call(receivedData);

              debugPrint(
                  'Received data: ${receivedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
            } catch (e) {
              debugPrint('Error converting received data: $e');
            }
          }
        } catch (e) {
          debugPrint('Error reading from serial port: $e');
          break;
        } finally {
          reader.releaseLock();
        }
      }

      reader.releaseLock();
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_port == null || !_port!.connected) {
      debugPrint('Serial port not connected');
      return;
    }

    try {
      final writer = _port!.writable?.getWriter();
      if (writer != null) {
        await writer.write(data.toJS).toDart;
        writer.releaseLock();
        debugPrint('Sent data: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }
    } catch (e) {
      debugPrint('Error sending data: $e');
    }
  }

  @override
  Future<Uint8List?> read(int length, {int timeout = 200}) async {
    if (!isDeviceConnected()) return null;

    // 等待数据或超时
    final completer = Completer<Uint8List?>();
    Timer? timeoutTimer;

    // 设置超时
    timeoutTimer = Timer(Duration(milliseconds: timeout), () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    // 检查是否已有数据
    if (readBuffer != null && readBuffer!.length >= length) {
      timeoutTimer.cancel();
      final result = Uint8List.fromList(readBuffer!.take(length).toList());
      readBuffer = readBuffer!.length > length
          ? Uint8List.fromList(readBuffer!.skip(length).toList())
          : null;
      return result;
    }

    // 等待新数据
    void Function(Uint8List)? originalCallback = _onDataReceived;
    _onDataReceived = (data) {
      originalCallback?.call(data);
      if (!completer.isCompleted && data.length >= length) {
        timeoutTimer?.cancel();
        final result = Uint8List.fromList(data.take(length).toList());
        readBuffer = data.length > length ? Uint8List.fromList(data.skip(length).toList()) : null;
        completer.complete(result);
      }
    };

    final result = await completer.future;
    _onDataReceived = originalCallback;

    return result;
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _onDataReceived = onData;
  }

  @override
  Future<void> disconnect() async {
    try {
      _keepReading = false;

      if (_reader != null) {
        await _reader!.cancel().toDart;
        _reader = null;
      }

      if (_port != null) {
        await _port!.close().toDart;
        _port = null;
      }

      connectedDeviceId = "";
      readBuffer = null;
      ConnectionManager.instance.updateConnectionStatus(false);

      debugPrint('Disconnected from serial port');
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  @override
  void openDeviceSelection(BuildContext context) {
    final currentContext = context;

    showDialog(
      context: currentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('serial.ports.title').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 请求新串口权限按钮
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('serial.request_new_port.title').tr(),
                  subtitle: const Text('serial.request_new_port.subtitle').tr(),
                  onTap: () {
                    Navigator.of(context).pop();
                    connect("request");
                  },
                ),
                const Divider(),
                // 已授权的串口列表
                Expanded(
                  child: StreamBuilder<List<SerialPort>>(
                    stream: scanResultsStream,
                    initialData: _availablePorts,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(child: Text('common.error_occurred').tr());
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(child: Text('serial.no_authorized_ports').tr());
                      } else {
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final port = snapshot.data![index];
                            final info = port.getInfo();
                            return ListTile(
                              leading: const Icon(Icons.usb),
                              title: Text('Serial Port $index'),
                              subtitle:
                                  Text('Vendor ID: ${info.usbVendorId ?? 'common.unknown'.tr()}\n'
                                      'Product ID: ${info.usbProductId ?? 'common.unknown'.tr()}'),
                              onTap: () {
                                Navigator.of(context).pop();
                                connect(index.toString());
                              },
                            );
                          },
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
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

    // 刷新可用端口列表
    startScan();
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    // Web Serial API 不支持重命名设备
    // 改为 toast 提示
    ToastManager().showInfoToast('serial.rename_not_supported_web'.tr());
  }

  Future<void> connectToSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    String? portId = prefs.getString('serialPortId');
    if (portId != null && portId.isNotEmpty) {
      await startScan();
      // 尝试连接到保存的端口
      for (int i = 0; i < _availablePorts.length; i++) {
        if (_availablePorts[i].getInfo().toString() == portId) {
          await connect(i.toString());
          break;
        }
      }
    }
  }
}
