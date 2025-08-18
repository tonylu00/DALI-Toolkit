import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'ble.dart';
import 'serial_ip.dart';
import 'connection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/toast.dart';

class ConnectionManager extends ChangeNotifier {
  static ConnectionManager? _instance;
  Connection _connection = BleManager();
  // 假设 checkGatewayType 返回 0 时为 type0 网关（需求: 仅对 type0 网关启用总线异常检测）
  int gatewayType = -1; // 未知
  String _busStatus = 'normal'; // normal / abnormal
  Timer? _busRecoverTimer;
  DateTime? _lastToastTime;
  String? _lastToastMsg;
  Duration toastThrottle = const Duration(seconds: 2);

  static ConnectionManager get instance {
    _instance ??= ConnectionManager();
    return _instance!;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionMethod = prefs.getString('connectionMethod') ?? 'BLE';
    if (connectionMethod == 'BLE') {
      if (_connection is BleManager) {
        debugPrint('BLE connection already initialized');
        return;
      }
      debugPrint('Initializing BLE connection');
      _connection = BleManager();
    } else if (connectionMethod == 'TCP') {
      _connection = TcpClient();
    } else if (connectionMethod == 'USB') {
      // Initialize USB connection if needed
      // _connection = UsbConnection();
    } else {
      debugPrint('Unknown connection method: $connectionMethod');
      return;
    }
  }

  void openDeviceSelection(BuildContext context) async {
    final perfs = await SharedPreferences.getInstance();
    final connectionMethod = perfs.getString('connectionMethod') ?? 'BLE';
    if (connectionMethod == 'BLE' && _connection is BleManager) {
      if (!context.mounted) return;
      _connection.openDeviceSelection(context);
    } else {
      // Show dialog for IP selection
    }
  }

  void updateConnectionStatus(bool isConnected) {
    notifyListeners();
  }

  void updateGatewayType(int type) {
    gatewayType = type;
    notifyListeners();
  }

  /// 确保已获取 gatewayType（仅首次获取），在连接建立后调用。
  Future<void> ensureGatewayType() async {
    if (gatewayType != -1) return; // 已有值
    final conn = _connection;
    try {
      // 参考 DaliComm.checkGatewayType 逻辑，避免直接依赖产生循环导入
      List<int> bytes1 = [0x01, 0x00, 0x00]; // USB type 0
      // 默认 gateway 地址 0
      int gateway = 0;
      List<int> bytes2 = [0x28, 0x01, gateway, 0x11, 0x00, 0x00, 0xff]; // Legacy type 1
      List<int> bytes3 = [
        0x28,
        0x01,
        gateway,
        0x11,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff
      ]; // New type 2

      await conn.send(Uint8List.fromList(bytes1));
      await Future.delayed(const Duration(milliseconds: 100));
      Uint8List? data = await conn.read(2, timeout: 100);
      if ((data != null && data.isNotEmpty) && (data[0] == 0x01 || data[0] == 0x05)) {
        gatewayType = 0; // USB
        notifyListeners();
        debugPrint("Gateway type detected: USB");
        return;
      }

      await conn.send(Uint8List.fromList(bytes2));
      await Future.delayed(const Duration(milliseconds: 100));
      data = await conn.read(2, timeout: 100);
      if (data != null && data.length == 2 && data[0] == gateway && data[1] >= 0) {
        gatewayType = 1; // Legacy 485
        notifyListeners();
        debugPrint("Gateway type detected: Legacy 485");
        return;
      }

      await conn.send(Uint8List.fromList(bytes3));
      await Future.delayed(const Duration(milliseconds: 100));
      data = await conn.read(2, timeout: 100);
      if (data != null && data.length == 2 && data[0] == gateway && data[1] >= 0) {
        gatewayType = 2; // New 485
        notifyListeners();
        debugPrint("Gateway type detected: New 485");
        return;
      }
      gatewayType = 0; // 视为 type0（需求中使用）
      notifyListeners();
      debugPrint("Could not detect gateway type, use 0");
    } catch (e) {
      // 检测失败保持 -1 以便之后可再尝试
      debugPrint('ensureGatewayType failed: $e');
    }
  }

  String get busStatus => _busStatus;

  bool canOperateBus() {
    // 可扩展加入其它条件（如连接状态、网关类型等）
    return _busStatus != 'abnormal';
  }

  /// 统一检查：设备连接 + 总线正常
  bool ensureReadyForOperation({bool showToast = true}) {
    final connected = _connection.isDeviceConnected();
    if (!connected) {
      if (showToast) {
        debugPrint('Device not connected');
        _showToastSafe('Device not connected');
      }
      return false;
    }
    if (!canOperateBus()) {
      if (showToast) {
        debugPrint('Bus abnormal');
        _showToastSafe('Bus abnormal');
      }
      return false;
    }
    return true;
  }

  void _showToastSafe(String msg) {
    try {
      final now = DateTime.now();
      if (_lastToastTime != null && _lastToastMsg == msg) {
        if (now.difference(_lastToastTime!) < toastThrottle) {
          // 节流：相同消息短时间内不再弹
          return;
        }
      }
      _lastToastTime = now;
      _lastToastMsg = msg;
      ToastManager().showErrorToast(msg);
    } catch (e) {
      debugPrint('Toast show failed: $e');
    }
  }

  void markBusAbnormal({Duration recoverAfter = const Duration(seconds: 5)}) {
    if (_busStatus == 'abnormal') {
      // 刷新计时器
      _busRecoverTimer?.cancel();
    }
    _busStatus = 'abnormal';
    _busRecoverTimer?.cancel();
    _busRecoverTimer = Timer(recoverAfter, () {
      _busStatus = 'normal';
      notifyListeners();
    });
    notifyListeners();
  }

  void resetBusStatus() {
    _busRecoverTimer?.cancel();
    _busStatus = 'normal';
    notifyListeners();
  }

  Connection get connection => _connection;
}
