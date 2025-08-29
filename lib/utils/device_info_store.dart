import 'dart:async';
import 'package:flutter/foundation.dart';

import '../dali/dali.dart';
import '../dali/log.dart';

/// In-memory device info cache, lives for app lifetime.
/// Auto-refresh after scan completes and on selection changes.
class DeviceInfoStore extends ChangeNotifier {
  DeviceInfoStore._internal() {
    _initStreams();
  }

  static final DeviceInfoStore instance = DeviceInfoStore._internal();

  final Map<int, DeviceInfo> _devices = <int, DeviceInfo>{};
  StreamSubscription<bool>? _scanSub;
  StreamSubscription<int>? _selSub;
  bool _isRefreshingBatch = false;

  void _initStreams() {
    // Listen scan state: when becomes false (finished), start batch refresh.
    _scanSub = Dali.instance.addr!.searchStateStream.listen((scanning) async {
      if (!scanning) {
        await refreshOnlineDevices();
      }
    });
    // Listen selection change; refresh the selected device quickly.
    _selSub = Dali.instance.addr!.selectedDeviceStream.listen((addr) async {
      await refresh(addr, silent: true);
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _selSub?.cancel();
    super.dispose();
  }

  DeviceInfo? get(int addr) => _devices[addr];

  /// Returns a read-only snapshot for UI.
  Map<int, DeviceInfo> get snapshot => Map.unmodifiable(_devices);

  Future<void> refreshOnlineDevices() async {
    if (_isRefreshingBatch) return;
    _isRefreshingBatch = true;
    try {
      final list = List<int>.from(Dali.instance.addr!.onlineDevices);
      for (final a in list) {
        await refresh(a, silent: true);
        // tiny delay to avoid flooding gateway
        await Future.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _isRefreshingBatch = false;
    }
  }

  /// Refresh one device info from bus.
  Future<void> refresh(int addr, {bool silent = false}) async {
    final base = Dali.instance.base!;
    final info = _devices.putIfAbsent(addr, () => DeviceInfo(addr: addr));
    try {
      final st = await base.getStatus(addr);
      info.status = st;
    } catch (e) {
      // keep previous status; mark offline if needed
      DaliLog.instance.debugLog('DeviceInfoStore.getStatus($addr) error: $e');
    }
    try {
      info.fadeTime = await base.getFadeTime(addr);
    } catch (e) {
      DaliLog.instance.debugLog('DeviceInfoStore.getFadeTime($addr) error: $e');
    }
    try {
      info.fadeRate = await base.getFadeRate(addr);
    } catch (e) {
      DaliLog.instance.debugLog('DeviceInfoStore.getFadeRate($addr) error: $e');
    }
    info.lastUpdated = DateTime.now();
    if (!silent) notifyListeners();
    // Even for silent updates, batch will call notify afterwards.
  }

  void touchNotify() => notifyListeners();
}

class DeviceInfo {
  DeviceInfo({required this.addr});
  final int addr;
  int? status; // 0x90 status bits
  int? fadeTime; // 0xA6 index (0..255)
  int? fadeRate; // 0xA7 index (0..255)
  DateTime? lastUpdated;
}
