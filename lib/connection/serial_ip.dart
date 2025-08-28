import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dalimaster/toast.dart';
import 'package:flutter/material.dart';
import 'package:dalimaster/dali/log.dart';
import 'manager.dart';

import 'connection.dart';

/// 通用缓冲 + 读取等待器封装
class _BufferedReader {
  Uint8List? _buffer;
  Completer<Uint8List?>? _pending;
  int? _pendingLen;
  Timer? _timer;

  void add(Uint8List data) {
    if (data.isEmpty) return;
    if (_buffer == null || _buffer!.isEmpty) {
      _buffer = Uint8List.fromList(data);
    } else {
      final merged = Uint8List(_buffer!.length + data.length);
      merged.setAll(0, _buffer!);
      merged.setAll(_buffer!.length, data);
      _buffer = merged;
    }
    _tryFulfill();
  }

  Future<Uint8List?> read(int len, int timeoutMs) {
    // 快速路径
    if (_buffer != null && _buffer!.length >= len) {
      final out = Uint8List.fromList(_buffer!.sublist(0, len));
      final remain = _buffer!.length - len;
      _buffer = remain > 0 ? Uint8List.fromList(_buffer!.sublist(len)) : null;
      return Future.value(out);
    }
    // 取消旧的
    if (_pending != null && !(_pending!.isCompleted)) {
      _pending!.complete(null);
    }
    _timer?.cancel();
    _pending = Completer<Uint8List?>();
    _pendingLen = len;
    _timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (_pending != null && !(_pending!.isCompleted)) {
        final c = _pending!;
        _pending = null;
        _pendingLen = null;
        c.complete(null);
      }
    });
    // 再尝试一次（避免 race）
    _tryFulfill();
    return _pending!.future;
  }

  void _tryFulfill() {
    if (_pending == null || _pendingLen == null) return;
    if (_buffer == null || _buffer!.length < _pendingLen!) return;
    final len = _pendingLen!;
    final out = Uint8List.fromList(_buffer!.sublist(0, len));
    final remain = _buffer!.length - len;
    _buffer = remain > 0 ? Uint8List.fromList(_buffer!.sublist(len)) : null;
    _timer?.cancel();
    final c = _pending!;
    _pending = null;
    _pendingLen = null;
    if (!c.isCompleted) c.complete(out);
  }

  void clear() {
    _timer?.cancel();
    if (_pending != null && !(_pending!.isCompleted)) {
      _pending!.complete(null);
    }
    _pending = null;
    _pendingLen = null;
    _buffer = null;
  }
}

class TcpClient implements Connection {
  Socket? _socket;
  bool _isConnected = false;
  final _reader = _BufferedReader();
  StreamSubscription<List<int>>? _sub;

  @override
  String connectedDeviceId = '';

  @override
  final String type = 'IP';
  String get protocol => 'TCP';

  @override
  Uint8List? readBuffer; // 兼容接口，内部使用 _reader

  @override
  Future<void> connect(String address, {int port = 12345}) async {
    disconnect();
    final s = await Socket.connect(address, port, timeout: const Duration(seconds: 5));
    _socket = s;
    _isConnected = true;
    connectedDeviceId = '${s.remoteAddress.address}:$port';
    _sub = s.listen((data) {
      final bytes = Uint8List.fromList(data);
      _reader.add(bytes);
      readBuffer = bytes; // 最近一次
    }, onError: (e) {
      DaliLog.instance.debugLog('TCP error: $e');
      disconnect();
    }, onDone: () {
      DaliLog.instance.debugLog('TCP done');
      disconnect();
    });
    DaliLog.instance.debugLog('TCP connected to $connectedDeviceId');
    ConnectionManager.instance.updateConnectionStatus(true);
    unawaited(ConnectionManager.instance.ensureGatewayType());
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_socket == null) return;
    try {
      _socket!.add(data);
    } catch (e) {
      DaliLog.instance.debugLog('TCP send error: $e');
    }
  }

  @override
  Future<Uint8List?> read(int len, {int timeout = 200}) async {
    if (!_isConnected) return null;
    return _reader.read(len, timeout);
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _sub?.cancel();
    if (_socket == null) return;
    _sub = _socket!.listen((data) {
      final u = Uint8List.fromList(data);
      _reader.add(u);
      readBuffer = u;
      onData(u);
    });
  }

  @override
  void disconnect() {
    _isConnected = false;
    _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    connectedDeviceId = '';
    _reader.clear();
    ConnectionManager.instance.updateConnectionStatus(false);
    ConnectionManager.instance.updateGatewayType(-1);
  }

  @override
  Future<void> startScan() async {
    // IP 连接不扫描
  }

  @override
  void stopScan() {}

  @override
  bool isDeviceConnected() => _isConnected;

  @override
  void openDeviceSelection(BuildContext context) {
    /* IP 连接弹窗由 ConnectionManager 统一处理 */
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    // 暂不支持命名 TCP 连接
    ToastManager().showInfoToast('Rename not supported');
  }
}

class UdpClient implements Connection {
  RawDatagramSocket? _socket;
  InternetAddress? _remoteAddress;
  int _remotePort = 0;
  final _reader = _BufferedReader();

  @override
  String connectedDeviceId = '';

  @override
  final String type = 'IP';
  String get protocol => 'UDP';

  @override
  Uint8List? readBuffer;

  @override
  Future<void> connect(String address, {int port = 12345}) async {
    disconnect();
    _remoteAddress = InternetAddress(address);
    _remotePort = port;
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
        .timeout(const Duration(seconds: 5));
    _socket = s;
    connectedDeviceId = '${_remoteAddress!.address}:$port';
    s.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? d;
        while ((d = s.receive()) != null) {
          final bytes = d!.data;
          _reader.add(bytes);
          readBuffer = bytes;
        }
      }
    });
    DaliLog.instance
        .debugLog('UDP ready to $connectedDeviceId (local ${s.address.address}:${s.port})');
    ConnectionManager.instance.updateConnectionStatus(true);
    unawaited(ConnectionManager.instance.ensureGatewayType());
  }

  @override
  Future<void> send(Uint8List data) async {
    final s = _socket;
    if (s == null || _remoteAddress == null) return;
    try {
      s.send(data, _remoteAddress!, _remotePort);
    } catch (e) {
      DaliLog.instance.debugLog('UDP send error: $e');
    }
  }

  @override
  Future<Uint8List?> read(int len, {int timeout = 200}) async {
    if (_socket == null) return null;
    return _reader.read(len, timeout);
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    final s = _socket;
    if (s == null) return;
    s.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? d;
        while ((d = s.receive()) != null) {
          final u = d!.data;
          _reader.add(u);
          readBuffer = u;
          onData(u);
        }
      }
    });
  }

  @override
  void disconnect() {
    _socket?.close();
    _socket = null;
    _remoteAddress = null;
    connectedDeviceId = '';
    _reader.clear();
    ConnectionManager.instance.updateConnectionStatus(false);
    ConnectionManager.instance.updateGatewayType(-1);
  }

  @override
  Future<void> startScan() async {}

  @override
  void stopScan() {}

  @override
  bool isDeviceConnected() => _socket != null;

  @override
  void openDeviceSelection(BuildContext context) {
    /* IP 连接弹窗由 ConnectionManager 统一处理 */
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    ToastManager().showInfoToast('Rename not supported');
  }
}

// 旧的 IP 弹窗与历史逻辑已迁移到 ConnectionManager，保留纯连接逻辑
