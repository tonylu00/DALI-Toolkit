import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'manager.dart';
import 'connection.dart';
import '../widgets/common/rename_device_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:fluttertoast/fluttertoast.dart';
import 'package:device_info_plus/device_info_plus.dart';

class BleManager implements Connection {
  static final List<BleDevice> _scanResults = [];
  static final Set<String> _uniqueDeviceIds = {};
  static final _scanResultsController = StreamController<List<BleDevice>>.broadcast();
  static Stream<List<BleDevice>> get scanResultsStream => _scanResultsController.stream;
  static final String serviceUuid = BleUuidParser.number(0xfff0);
  static final String readUuid = BleUuidParser.number(0xfff1);
  static final String writeUuid = BleUuidParser.number(0xfff1);
  static bool isScanning = false;

  @override
  String connectedDeviceId = "";
  @override
  final String type = 'BLE';

  @override
  Uint8List? readBuffer;

  @override
  bool isDeviceConnected() {
    if (connectedDeviceId.isEmpty) {
      debugPrint('No device connected');
      return false;
    }
    return true;
  }

  @override
  Future<void> startScan() async {
    if (!kIsWeb) {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      if (state != AvailabilityState.poweredOn) {
        debugPrint('Bluetooth is not powered on');
        return;
      }
    }
    await _startScanCore();
  }

  Future<void> _startScanCore() async {
    _scanResults.clear();
    _uniqueDeviceIds.clear();
    UniversalBle.onScanResult = (bleDevice) {
      if (bleDevice.name != null &&
          bleDevice.name!.isNotEmpty &&
          !_uniqueDeviceIds.contains(bleDevice.deviceId)) {
        _scanResults.add(bleDevice);
        _uniqueDeviceIds.add(bleDevice.deviceId);
        _scanResultsController.add(_scanResults);
        debugPrint('Scan result: $bleDevice');
      }
    };
    await disconnect();
    UniversalBle.startScan(scanFilter: ScanFilter(withServices: [serviceUuid]));
  }

  @override
  void stopScan() {
    UniversalBle.stopScan();
  }

  @override
  Future<void> connect(String deviceId, {int? port}) async {
    stopScan();
    UniversalBle.onConnectionChange = ((deviceId, isConnected, error) {
      debugPrint('OnConnectionChange $deviceId, $isConnected Error: $error');
      if (isConnected) {
        connectedDeviceId = deviceId;
        // 先检测 gatewayType 后再广播连接状态
        ConnectionManager.instance.ensureGatewayType().then((_) {
          ConnectionManager.instance.updateConnectionStatus(true);
        });
        final prefs = SharedPreferences.getInstance();
        prefs.then((prefs) {
          prefs.setString('deviceId', deviceId);
        });
        UniversalBle.discoverServices(deviceId);
        UniversalBle.subscribeNotifications(deviceId, serviceUuid, readUuid);
        UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
          debugPrint(
              'HEX Value changed: ${value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          readBuffer = value;
          _handleBusMonitor(value);
        };
        debugPrint('Connected to $deviceId');
      } else if (error != null) {
        debugPrint('Error: $error');
      } else {
        connectedDeviceId = "";
        readBuffer = null;
        ConnectionManager.instance.updateConnectionStatus(false);
        ConnectionManager.instance.resetBusStatus();
        ConnectionManager.instance.updateGatewayType(-1);
      }
    });
    await disconnect();
    await UniversalBle.connect(deviceId);
  }

  void _handleBusMonitor(Uint8List value) {
    final manager = ConnectionManager.instance;
    // 仅对 type0 网关启用
    if (manager.gatewayType != 0) return;
    // 空闲状态下收到两个字节依次为 0xFF 0xFD 表示总线异常
    if (value.length >= 2) {
      for (int i = 0; i < value.length - 1; i++) {
        if (value[i] == 0xff && value[i + 1] == 0xfd) {
          manager.markBusAbnormal();
          break;
        }
      }
    }
  }

  // 网关类型检测已迁移至 ConnectionManager.ensureGatewayType

  Future<void> connectToSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('deviceId');
    if (deviceId != null) {
      connect(deviceId);
    }
  }

  @override
  Future<void> disconnect() async {
    String deviceId = connectedDeviceId;
    if (deviceId.isEmpty) {
      if (kIsWeb) {
        debugPrint('No device connected, skipping disconnect on Web');
        return;
      }
      List<BleDevice> devices = await UniversalBle.getSystemDevices(withServices: [serviceUuid]);
      for (BleDevice device in devices) {
        UniversalBle.disconnect(device.deviceId);
        debugPrint('Disconnected from ${device.deviceId}');
      }
      return;
    }
    UniversalBle.disconnect(deviceId);
    connectedDeviceId = "";
    ConnectionManager.instance.updateConnectionStatus(false);
    debugPrint('Disconnected from $deviceId');
  }

  void sendCommand(String command) {
    String deviceId = connectedDeviceId;
    if (deviceId.isEmpty) {
      return;
    }
    UniversalBle.write(
      deviceId,
      serviceUuid,
      writeUuid,
      Uint8List.fromList(command.codeUnits),
      withoutResponse: true,
    );
  }

  @override
  Future<Uint8List?> read(int len, {int timeout = 200}) async {
    if (!ConnectionManager.instance.canOperateBus()) {
      debugPrint('ble:read blocked (bus abnormal)');
      return null;
    }
    if (!isDeviceConnected()) if (!await restoreExistConnection()) return null;
    try {
      final value = await UniversalBle.read(connectedDeviceId, serviceUuid, readUuid,
          timeout: Duration(milliseconds: timeout));
      debugPrint('Read value: $value');
      return value;
    } catch (e) {
      debugPrint('Error reading characteristic: $e');
    }
    return null;
  }

  @override
  Future<void> send(Uint8List value) async {
    if (!ConnectionManager.instance.canOperateBus()) {
      debugPrint('ble:send blocked (bus abnormal)');
      return;
    }
    if (!isDeviceConnected()) if (!await restoreExistConnection()) return;
    int retry = 0;
    while (retry < 3) {
      retry++;
      try {
        await UniversalBle.write(connectedDeviceId, serviceUuid, writeUuid, value);
      } catch (e) {
        debugPrint('Error writing characteristic: $e');
        continue;
      }
      break;
    }
  }

  @override
  void openDeviceSelection(BuildContext context) {
    _showPermissionRationaleThenScan(context);
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    if (!isDeviceConnected()) return;

    RenameDeviceDialog.show(
      context,
      currentName: currentName,
      connectedDeviceId: connectedDeviceId,
      sendCommand: (data) => send(data),
    );
  }

  @override
  void onReceived(void Function(Uint8List) onData) {
    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
      _handleBusMonitor(value);
      onData(value);
    };
  }

  Future<bool> restoreExistConnection() async {
    if (connectedDeviceId.isEmpty) {
      List<BleDevice> devices = await UniversalBle.getSystemDevices(withServices: [serviceUuid]);
      if (devices.isEmpty) {
        ConnectionManager.instance.updateConnectionStatus(false);
        return false;
      }
      for (BleDevice device in devices) {
        connectedDeviceId = device.deviceId;
        debugPrint('Restore connection from ${device.deviceId}');
      }
    } else {
      debugPrint('Already connected to $connectedDeviceId');
    }
    ConnectionManager.instance.updateConnectionStatus(true);
    return true;
  }

  static List<BleDevice> get scanResults => _scanResults;

  // Ensure correct runtime permissions for BLE scanning.
  // Android 12+ (SDK 31+) needs bluetoothScan & bluetoothConnect.
  // Android 11 and below need location (fine) permission.
  Future<bool> _ensurePermissions() async {
    try {
      if (kIsWeb || !Platform.isAndroid) return true;
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 31) {
        // Android 12+
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        if (scan.isGranted && connect.isGranted) return true;
        if (scan.isPermanentlyDenied || connect.isPermanentlyDenied) openAppSettings();
        return false;
      } else {
        // Android 11 及以下
        final loc = await Permission.location.request();
        if (loc.isGranted) return true;
        if (loc.isPermanentlyDenied) openAppSettings();
        return false;
      }
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  Future<void> _showPermissionRationaleThenScan(BuildContext context) async {
    // 如果是 Web 直接打开扫描
    if (kIsWeb) {
      await _startScanCore();
      _showScanDialog(context);
      return;
    }
    // 仅 Android 需要解释；其它平台直接扫描
    if (!Platform.isAndroid) {
      await _startScanCore();
      _showScanDialog(context);
      return;
    }
    // 先判断是否已经全部权限 OK
    bool preGranted = await _permissionsAlreadyGranted();
    if (preGranted) {
      await _startScanCore();
      _showScanDialog(context);
      return;
    }
    // 说明对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('权限请求').tr(),
          content:
              const Text('需要蓝牙扫描与连接权限 (Android 12+)，或定位权限 (Android 11 及以下) 来搜索并连接到网关设备。请授予以继续。')
                  .tr(),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // 用户拒绝，不再弹系统权限，提示 toast
                Fluttertoast.showToast(msg: tr('权限被取消，无法扫描设备'));
              },
              child: const Text('取消').tr(),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                bool ok = await _ensurePermissions();
                if (!ok) {
                  Fluttertoast.showToast(msg: tr('未授予权限，无法扫描设备'));
                  return;
                }
                await _startScanCore();
                _showScanDialog(context);
              },
              child: const Text('继续').tr(),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _permissionsAlreadyGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      return scan.isGranted && connect.isGranted;
    } else {
      final loc = await Permission.location.status;
      return loc.isGranted;
    }
  }

  void _showScanDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ble.device.title').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<BleDevice>>(
              stream: BleManager.scanResultsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('common.error_occurred').tr());
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('device.no_devices_found').tr());
                } else {
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(snapshot.data![index].name ?? 'common.unknown').tr(),
                        subtitle: Text(
                            'ID: ${snapshot.data![index].deviceId}\nRSSI: ${snapshot.data![index].rssi}'),
                        onTap: () {
                          stopScan();
                          connect(snapshot.data![index].deviceId);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                }
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                stopScan();
                Navigator.of(context).pop();
              },
              child: const Text('common.close').tr(),
            ),
          ],
        );
      },
    );
  }
}
