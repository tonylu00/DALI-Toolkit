import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '/toast.dart';
import 'connection.dart';
import 'manager.dart';

/// USB 串口实现 (Desktop / Linux / macOS / Windows)
class SerialUsbConnection implements Connection {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;
  final List<String> _availablePorts = [];
  final _scanResultsController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get scanResultsStream => _scanResultsController.stream;

  void Function(Uint8List data)? _onDataReceived;

  @override
  String connectedDeviceId = '';
  @override
  final String type = 'Serial USB';
  @override
  Uint8List? readBuffer;

  bool _isScanning = false;

  // 挂起的 read 请求（避免对单订阅流重复 listen）
  Completer<Uint8List?>? _pendingRead;
  int? _pendingReadLength;
  Timer? _pendingReadTimer;

  @override
  bool isDeviceConnected() => _port != null && _port!.isOpen;

  @override
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    try {
      _availablePorts
        ..clear()
        ..addAll(SerialPort.availablePorts);
      _scanResultsController.add(List.of(_availablePorts));
    } catch (e) {
      debugPrint('Serial USB scan error: $e');
    } finally {
      _isScanning = false;
    }
  }

  @override
  void stopScan() {
    _isScanning = false; // 轮询方式下可加入 Timer.cancel
  }

  @override
  Future<void> connect(String address, {int port = 0}) async {
    await disconnect();
    int attempts = 0;
    while (attempts < 3) {
      attempts++;
      try {
        // address 直接是设备路径/名称，若是索引则解析
        String devicePath = address;
        if (!_availablePorts.contains(devicePath)) {
          final idx = int.tryParse(address);
          if (idx != null && idx >= 0 && idx < _availablePorts.length) {
            devicePath = _availablePorts[idx];
          }
        }
        if (!_availablePorts.contains(devicePath)) {
          debugPrint('Invalid serial device: $address');
          ToastManager().showErrorToast('Invalid serial device');
          return;
        }
        final sp = SerialPort(devicePath);
        if (!sp.openReadWrite()) {
          debugPrint('Failed to open $devicePath: ${SerialPort.lastError}');
          if (attempts >= 3) ToastManager().showErrorToast('USB open failed');
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        final config = SerialPortConfig()
          ..baudRate = 9600
          ..bits = 8
          ..parity = 0
          ..stopBits = 1
          ..setFlowControl(SerialPortFlowControl.none);
        sp.config = config;

        _port = sp;
        connectedDeviceId = devicePath;
        ConnectionManager.instance.updateConnectionStatus(true);

        final prefs = await SharedPreferences.getInstance();
        prefs.setString('serialUsbPath', devicePath);

        _reader = SerialPortReader(sp, timeout: 50);
        _subscription = _reader!.stream.listen(_handleData, onError: (e) {
          debugPrint('Serial read error: $e');
        }, onDone: () {
          debugPrint('Serial stream done');
        }, cancelOnError: false);

        debugPrint('Serial USB connected: $devicePath');
        unawaited(ConnectionManager.instance.ensureGatewayType());
        return; // success
      } catch (e) {
        debugPrint('Serial USB connect attempt $attempts error: $e');
        if (attempts >= 3) {
          ToastManager().showErrorToast('USB connect failed');
          ConnectionManager.instance.updateConnectionStatus(false);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _handleData(Uint8List data) {
    // 累积到 readBuffer
    if (data.isEmpty) return;
    if (readBuffer == null || readBuffer!.isEmpty) {
      readBuffer = Uint8List.fromList(data);
    } else {
      final merged = Uint8List(readBuffer!.length + data.length);
      merged.setAll(0, readBuffer!);
      merged.setAll(readBuffer!.length, data);
      readBuffer = merged;
    }
    _onDataReceived?.call(data);
    debugPrint('USB recv: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _tryCompletePendingRead();
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_port == null || !_port!.isOpen) {
      debugPrint('Serial USB not connected');
      return;
    }
    try {
      final written = _port!.write(data, timeout: 100);
      if (written != data.length) {
        debugPrint('Partial write: $written/${data.length}');
      } else {
        debugPrint('USB sent: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
      }
    } catch (e) {
      debugPrint('Serial USB send error: $e');
    }
  }

  @override
  Future<Uint8List?> read(int length, {int timeout = 200}) async {
    if (!isDeviceConnected()) return null;
    // 快速路径：缓冲已有
    if (readBuffer != null && readBuffer!.length >= length) {
      final out = Uint8List.fromList(readBuffer!.sublist(0, length));
      final remain = readBuffer!.length - length;
      readBuffer = remain > 0 ? Uint8List.fromList(readBuffer!.sublist(length)) : null;
      return out;
    }
    // 若已有挂起读取，先取消（或直接复用策略）。这里选择取消旧的以避免等待链表复杂性。
    if (_pendingRead != null && !(_pendingRead!.isCompleted)) {
      _pendingRead!.complete(null); // 让旧调用返回 null
    }
    _pendingReadTimer?.cancel();

    final completer = Completer<Uint8List?>();
    _pendingRead = completer;
    _pendingReadLength = length;
    _pendingReadTimer = Timer(Duration(milliseconds: timeout), () {
      if (!completer.isCompleted) {
        _pendingRead = null;
        _pendingReadLength = null;
        completer.complete(null);
      }
    });

    // 设定后立即尝试一次（避免 race）
    _tryCompletePendingRead();
    return completer.future;
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _onDataReceived = onData;
  }

  @override
  Future<void> disconnect() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      _reader = null;
      _pendingReadTimer?.cancel();
      if (_pendingRead != null && !(_pendingRead!.isCompleted)) {
        _pendingRead!.complete(null);
      }
      _pendingRead = null;
      _pendingReadLength = null;
      if (_port != null) {
        if (_port!.isOpen) {
          _port!.close();
        }
        _port!.dispose();
        _port = null;
      }
      readBuffer = null;
      connectedDeviceId = '';
      ConnectionManager.instance.updateConnectionStatus(false);
      ConnectionManager.instance.updateGatewayType(-1);
      debugPrint('Serial USB disconnected');
    } catch (e) {
      debugPrint('Serial USB disconnect error: $e');
    }
  }

  void _tryCompletePendingRead() {
    if (_pendingRead == null || _pendingReadLength == null) return;
    if (readBuffer == null || readBuffer!.length < _pendingReadLength!) return;
    final len = _pendingReadLength!;
    final out = Uint8List.fromList(readBuffer!.sublist(0, len));
    final remain = readBuffer!.length - len;
    readBuffer = remain > 0 ? Uint8List.fromList(readBuffer!.sublist(len)) : null;
    _pendingReadTimer?.cancel();
    final c = _pendingRead!;
    _pendingRead = null;
    _pendingReadLength = null;
    if (!c.isCompleted) c.complete(out);
  }

  @override
  void openDeviceSelection(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('USB Serial Devices').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<String>>(
              stream: scanResultsStream,
              initialData: _availablePorts,
              builder: (context, snapshot) {
                final ports = snapshot.data ?? [];
                if (ports.isEmpty) {
                  return Center(child: const Text('No devices').tr());
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: ports.length,
                  itemBuilder: (c, i) {
                    final p = ports[i];
                    return ListTile(
                      leading: const Icon(Icons.usb),
                      title: Text(p),
                      subtitle: Text('Index: $i'),
                      onTap: () {
                        Navigator.of(context).pop();
                        connect(p);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => startScan(),
              child: const Text('Refresh').tr(),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close').tr(),
            ),
          ],
        );
      },
    );
    startScan();
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    ToastManager().showInfoToast('Device renaming not supported'.tr());
  }

  Future<void> connectToSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('serialUsbPath');
    if (saved != null && saved.isNotEmpty) {
      await startScan();
      if (_availablePorts.contains(saved)) {
        await connect(saved);
      }
    }
  }
}
