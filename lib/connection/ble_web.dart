import 'package:flutter/material.dart';
import 'package:dalimaster/dali/log.dart';
import 'package:universal_ble/universal_ble.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'manager.dart';
import 'connection.dart';
import '../widgets/common/rename_device_dialog.dart';

class BleWebManager implements Connection {
  static final List<BleDevice> _scanResults = [];
  static final Set<String> _uniqueDeviceIds = {};
  static final _scanResultsController =
      StreamController<List<BleDevice>>.broadcast();
  static Stream<List<BleDevice>> get scanResultsStream =>
      _scanResultsController.stream;
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
      DaliLog.instance.debugLog('No device connected');
      return false;
    }
    return true;
  }

  @override
  Future<void> startScan() async {
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
        DaliLog.instance.debugLog('Scan result: $bleDevice');
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
      DaliLog.instance
          .debugLog('OnConnectionChange $deviceId, $isConnected Error: $error');
      if (isConnected) {
        connectedDeviceId = deviceId;
        ConnectionManager.instance.updateConnectionStatus(true);
        final prefs = SharedPreferences.getInstance();
        prefs.then((prefs) {
          prefs.setString('deviceId', deviceId);
        });
        UniversalBle.discoverServices(deviceId);
        UniversalBle.subscribeNotifications(deviceId, serviceUuid, readUuid);
        UniversalBle.onValueChange =
            (String deviceId, String characteristicId, Uint8List value) {
          DaliLog.instance.debugLog(
              'HEX Value changed: ${value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          readBuffer = value;
          _handleBusMonitor(value);
        };
        DaliLog.instance.debugLog('Connected to $deviceId');
        Future.delayed(const Duration(milliseconds: 500));
        unawaited(ConnectionManager.instance.ensureGatewayType());
      } else if (error != null) {
        DaliLog.instance.debugLog('Error: $error');
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
    if (manager.gatewayType != 0) return;
    if (value.length >= 2) {
      for (int i = 0; i < value.length - 1; i++) {
        if (value[i] == 0xff && value[i + 1] == 0xfd) {
          manager.markBusAbnormal();
          break;
        }
      }
    }
  }

  @override
  Future<void> disconnect() async {
    String deviceId = connectedDeviceId;
    if (deviceId.isEmpty) {
      DaliLog.instance
          .debugLog('No device connected, skipping disconnect on Web');
      return;
    }
    List<BleDevice> devices =
        await UniversalBle.getSystemDevices(withServices: [serviceUuid]);
    for (BleDevice device in devices) {
      UniversalBle.disconnect(device.deviceId);
      DaliLog.instance.debugLog('Disconnected from ${device.deviceId}');
    }
    connectedDeviceId = "";
    readBuffer = null;
    ConnectionManager.instance.updateConnectionStatus(false);
    ConnectionManager.instance.resetBusStatus();
    ConnectionManager.instance.updateGatewayType(-1);
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
      DaliLog.instance.debugLog('ble:read blocked (bus abnormal)');
      return null;
    }
    if (!isDeviceConnected()) return null;
    try {
      final value = await UniversalBle.read(
          connectedDeviceId, serviceUuid, readUuid,
          timeout: Duration(milliseconds: timeout));
      DaliLog.instance.debugLog('Read value: $value');
      return value;
    } catch (e) {
      DaliLog.instance.debugLog('Error reading characteristic: $e');
    }
    return null;
  }

  @override
  Future<void> send(Uint8List value) async {
    if (!ConnectionManager.instance.canOperateBus()) {
      DaliLog.instance.debugLog('ble:send blocked (bus abnormal)');
      return;
    }
    if (!isDeviceConnected()) return;
    int retry = 0;
    while (retry < 3) {
      retry++;
      try {
        await UniversalBle.write(
            connectedDeviceId, serviceUuid, writeUuid, value);
      } catch (e) {
        DaliLog.instance.debugLog('Error writing characteristic: $e');
        continue;
      }
      break;
    }
  }

  @override
  void openDeviceSelection(BuildContext context) {
    _showScanDialog(context);
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
    UniversalBle.onValueChange =
        (String deviceId, String characteristicId, Uint8List value) {
      _handleBusMonitor(value);
      onData(value);
    };
  }

  Future<bool> restoreExistConnection() async {
    if (connectedDeviceId.isEmpty) {
      List<BleDevice> devices =
          await UniversalBle.getSystemDevices(withServices: [serviceUuid]);
      if (devices.isEmpty) {
        ConnectionManager.instance.updateConnectionStatus(false);
        return false;
      }
      for (BleDevice device in devices) {
        connectedDeviceId = device.deviceId;
        DaliLog.instance.debugLog('Restore connection from ${device.deviceId}');
      }
    } else {
      DaliLog.instance.debugLog('Already connected to $connectedDeviceId');
    }
    ConnectionManager.instance.updateConnectionStatus(true);
    return true;
  }

  static List<BleDevice> get scanResults => _scanResults;

  void _showScanDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ble.device.title').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<BleDevice>>(
              stream: BleWebManager.scanResultsStream,
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
                        title:
                            Text(snapshot.data![index].name ?? 'common.unknown')
                                .tr(),
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
