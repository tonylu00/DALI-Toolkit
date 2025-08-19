import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '/toast.dart';
import 'connection.dart';
import 'manager.dart';
import 'dart:io' show Platform;

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

  bool _autoReconnectEnabled = true;
  int _autoReconnectInterval = 2000; // ms
  int _autoReconnectMaxAttempts = 5;
  int _currentReconnectAttempts = 0;
  bool _manuallyDisconnected = false;
  Timer? _reconnectTimer;
  Timer? _portMonitorTimer;

  bool _suppressResetAttempts = false; // 防止自动重连时被重置计数

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

  Future<void> _loadReconnectPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _autoReconnectEnabled = prefs.getBool('autoReconnectEnabled') ?? true;
    _autoReconnectInterval = prefs.getInt('autoReconnectInterval') ?? 2000;
    _autoReconnectMaxAttempts = prefs.getInt('autoReconnectMaxAttempts') ?? 5;
  }

  void _scheduleReconnect() {
    if (!_autoReconnectEnabled) return; // not enabled
    if (_manuallyDisconnected) return; // user initiated
    if (_currentReconnectAttempts >= _autoReconnectMaxAttempts) {
      debugPrint('Serial USB auto-reconnect reached max attempts: $_currentReconnectAttempts');
      // 放弃后清空设备 ID，通知上层
      if (connectedDeviceId.isNotEmpty) {
        // 完整断开，清除保存的路径（不再 keepSavedPath）
        _internalDisconnect(manual: false, keepSavedPath: false);
      }
      _manuallyDisconnected = true; // 防止继续调度
      return; // exceed
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _autoReconnectInterval), () async {
      _currentReconnectAttempts++;
      debugPrint('Serial USB auto-reconnect attempt: $_currentReconnectAttempts');
      final target = connectedDeviceId.isNotEmpty ? connectedDeviceId : await _getSavedDevice();
      if (target.isEmpty) {
        // 没有目标，直接视为失败并清空
        _internalDisconnect(manual: false, keepSavedPath: false);
        _manuallyDisconnected = true;
        return;
      }
      _suppressResetAttempts = true; // 下次 connect 不重置计数
      await connect(target);
      if (isDeviceConnected()) {
        debugPrint('Serial USB auto-reconnect success');
        _currentReconnectAttempts = 0;
      } else {
        _scheduleReconnect();
      }
    });
  }

  Future<String> _getSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('serialUsbPath') ?? '';
  }

  @override
  Future<void> connect(String address, {int port = 0}) async {
    await _loadReconnectPrefs();
    // 连接流程开始前确保标记为非手动断开（允许后续自动重连）
    _manuallyDisconnected = false;
    if (!_suppressResetAttempts) {
      _currentReconnectAttempts = 0; // 正常用户触发连接重置计数
    } else {
      // 自动重连路径，仅使用一次后释放
      _suppressResetAttempts = false;
    }
    // 仅当当前已连接时执行清理，且不要标记为 manual（否则后续 scheduleReconnect 会被阻断）
    if (isDeviceConnected() || _port != null) {
      await _internalDisconnect(manual: false, keepSavedPath: true);
    }
    int attempts = 0;
    final int maxAttemptsThisRound = _suppressResetAttempts ? 1 : 3; // 自动重连只尝试一次
    while (attempts < maxAttemptsThisRound) {
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
          if (attempts >= maxAttemptsThisRound) ToastManager().showErrorToast('USB open failed');
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

        _attachReader(sp);

        debugPrint('Serial USB connected: $devicePath');
        unawaited(ConnectionManager.instance.ensureGatewayType());
        // After successful connection:
        _startPortMonitor();
        // 确保成功连接后不被视为手动断开
        _manuallyDisconnected = false;
        return; // success
      } catch (e) {
        debugPrint('Serial USB connect attempt $attempts/$maxAttemptsThisRound error: $e');
        if (attempts >= maxAttemptsThisRound) {
          ToastManager().showErrorToast('USB connect failed');
          ConnectionManager.instance.updateConnectionStatus(false);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  void _attachReader(SerialPort sp) {
    _reader = SerialPortReader(sp, timeout: 50);
    _subscription = _reader!.stream.listen(_handleData, onError: (e) {
      _handlePortClosedOrError(e);
    }, onDone: () {
      _handlePortClosedOrError();
    }, cancelOnError: false);
  }

  void _handleData(Uint8List data) {
    if (data.isEmpty) return;
    // 先回调原始数据（确保上层能及时收到分片），再累积
    _onDataReceived?.call(data);
    // 累积到 readBuffer
    if (readBuffer == null || readBuffer!.isEmpty) {
      readBuffer = Uint8List.fromList(data);
    } else {
      final merged = Uint8List(readBuffer!.length + data.length);
      merged.setAll(0, readBuffer!);
      merged.setAll(readBuffer!.length, data);
      readBuffer = merged;
    }
    _handleBusMonitor(data);
    debugPrint('USB recv: ${data.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
    _tryCompletePendingRead();
  }

  void _handleBusMonitor(Uint8List chunk) {
    final manager = ConnectionManager.instance;
    if (manager.gatewayType != 0) return; // only for type0
    if (chunk.length < 2) return;
    for (int i = 0; i < chunk.length - 1; i++) {
      if (chunk[i] == 0xff && chunk[i + 1] == 0xfd) {
        manager.markBusAbnormal();
        break;
      }
    }
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
    if (readBuffer != null && readBuffer!.isNotEmpty) {
      if (readBuffer!.length >= length) {
        final out = Uint8List.fromList(readBuffer!.sublist(0, length));
        final remain = readBuffer!.length - length;
        readBuffer = remain > 0 ? Uint8List.fromList(readBuffer!.sublist(length)) : null;
        return out;
      } else {
        // 若缓冲不足，继续等待，但先复制当前（用于超时返回）
      }
    }
    // 取消旧挂起
    if (_pendingRead != null && !(_pendingRead!.isCompleted)) {
      _pendingRead!.complete(null);
    }
    _pendingReadTimer?.cancel();

    final completer = Completer<Uint8List?>();
    _pendingRead = completer;
    _pendingReadLength = length;
    _pendingReadTimer = Timer(Duration(milliseconds: timeout), () {
      if (!completer.isCompleted) {
        // 超时：如果缓冲里有任意数据则返回部分，否则 null
        Uint8List? partial;
        if (readBuffer != null && readBuffer!.isNotEmpty) {
          final take = readBuffer!.length < length ? readBuffer!.length : length;
          partial = Uint8List.fromList(readBuffer!.sublist(0, take));
          final remain = readBuffer!.length - take;
          readBuffer = remain > 0 ? Uint8List.fromList(readBuffer!.sublist(take)) : null;
        }
        _pendingRead = null;
        _pendingReadLength = null;
        completer.complete(partial);
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

  Future<void> _internalDisconnect({required bool manual, bool keepSavedPath = false}) async {
    if (manual)
      _manuallyDisconnected = true;
    else
      _manuallyDisconnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
        try {
          if (_port!.isOpen) {
            _port!.close();
          }
        } catch (_) {}
        try {
          _port!.dispose();
        } catch (_) {}
        _port = null;
      }
      readBuffer = null;
      if (!keepSavedPath) connectedDeviceId = '';
      ConnectionManager.instance.updateConnectionStatus(false);
      ConnectionManager.instance.updateGatewayType(-1);
      debugPrint('Serial USB ${manual ? 'manual' : 'auto'} disconnected');
    } catch (e) {
      debugPrint('Serial USB internal disconnect error: $e');
    } finally {
      if (!manual && !_autoReconnectEnabled) {
        _manuallyDisconnected = true; // prevent schedule if disabled
      }
      if (_port == null) _stopPortMonitor();
    }
  }

  void _startPortMonitor() {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return; // desktop only
    _portMonitorTimer?.cancel();
    _portMonitorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_port == null || !_port!.isOpen) return; // not connected
      List<String> now = [];
      try {
        now = SerialPort.availablePorts;
      } catch (_) {}
      final path = connectedDeviceId;
      if (path.isEmpty) return;
      final present = now.contains(path);
      if (!present) {
        debugPrint('Serial USB device removed (poll)');
        // physical removal; treat as error/closed
        _handlePhysicalRemoval();
      }
    });
  }

  void _stopPortMonitor() {
    _portMonitorTimer?.cancel();
    _portMonitorTimer = null;
  }

  void _handlePhysicalRemoval() async {
    // Force close if still open to release resources
    try {
      if (_port != null && _port!.isOpen) {
        _port!.close();
      }
    } catch (_) {}
    if (_autoReconnectEnabled) {
      _internalDisconnect(manual: false, keepSavedPath: true);
      _scheduleReconnect();
    } else {
      await disconnect();
    }
  }

  @override
  Future<void> disconnect() async {
    await _internalDisconnect(manual: true);
  }

  void _handlePortClosedOrError([Object? e]) async {
    if (e != null) debugPrint('Serial USB port error/closed: $e');
    if (_port != null && _port!.isOpen) return; // still open
    if (!_autoReconnectEnabled) {
      await _internalDisconnect(manual: false);
      return;
    }
    await _internalDisconnect(manual: false, keepSavedPath: true);
    _scheduleReconnect();
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
