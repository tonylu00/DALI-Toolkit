import 'package:flutter/material.dart';
import 'ble.dart';
import 'serial_ip.dart';
import 'connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionManager extends ChangeNotifier {
  static ConnectionManager? _instance;
  Connection _connection = BleManager();

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
    } else {
      _connection = TcpClient();
    }
  }

  void showDeviceSelectionDialog(BuildContext context) async {
    final perfs = await SharedPreferences.getInstance();
    final connectionMethod = perfs.getString('connectionMethod') ?? 'BLE';
    if (connectionMethod == 'BLE' && _connection is BleManager) {
      if (!context.mounted) return;
      _connection.showDevicesDialog(context);
    } else {
      // Show dialog for IP selection
    }
  }

  void updateConnectionStatus(bool isConnected) {
    notifyListeners();
  }

  Connection get connection => _connection;
}