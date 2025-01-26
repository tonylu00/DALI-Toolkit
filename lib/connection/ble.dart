import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'manager.dart';
import 'connection.dart';

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
    AvailabilityState state = await UniversalBle.getBluetoothAvailabilityState();
    // Start scan only if Bluetooth is powered on
    if (state == AvailabilityState.poweredOn) {
      debugPrint('Bluetooth is powered on');
    } else {
      debugPrint('Bluetooth is not powered on');
      return;
    }
    _scanResults.clear();
    _uniqueDeviceIds.clear();
    UniversalBle.onScanResult = (bleDevice) {
      if (bleDevice.name != null && bleDevice.name!.isNotEmpty && !_uniqueDeviceIds.contains(bleDevice.deviceId)) {
        _scanResults.add(bleDevice);
        _uniqueDeviceIds.add(bleDevice.deviceId);
        _scanResultsController.add(_scanResults);
        debugPrint('Scan result: $bleDevice');
      }
    };
    await disconnect();
    UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [serviceUuid],
      ),
    );
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
        ConnectionManager.instance.updateConnectionStatus(true);
        final prefs = SharedPreferences.getInstance();
        prefs.then((prefs) {
          prefs.setString('deviceId', deviceId);
        });
        UniversalBle.discoverServices(deviceId);
        UniversalBle.setNotifiable(deviceId, serviceUuid, readUuid, BleInputProperty.notification);
        UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
          debugPrint('HEX Value changed: ${value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}');
          readBuffer = value;
        };
        debugPrint('Connected to $deviceId');
      } else if (error != null) {
        debugPrint('Error: $error');
      } else {
        connectedDeviceId = "";
        readBuffer = null;
        ConnectionManager.instance.updateConnectionStatus(false);
      }
    });
    await disconnect();
    await UniversalBle.connect(deviceId);
  }

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
    UniversalBle.writeValue(
      deviceId,
      serviceUuid,
      writeUuid,
      Uint8List.fromList(command.codeUnits),
      BleOutputProperty.withoutResponse,
    );
  }

  @override
  Future<Uint8List?> read(int len, {int timeout = 200}) async {
    if (!isDeviceConnected()) if(!await restoreExistConnection()) return null;
    try {
      final value = await UniversalBle.readValue(connectedDeviceId, serviceUuid, readUuid, timeout: Duration(milliseconds: timeout));
      debugPrint('Read value: $value');
      return value;
    } catch (e) {
      debugPrint('Error reading characteristic: $e');
    }
    return null;
  }

  @override
  Future<void> send(Uint8List value) async {
    if (!isDeviceConnected()) if(!await restoreExistConnection()) return;
    int retry = 0;
    while (retry < 3) {
      retry++;
      try {
        await UniversalBle.writeValue(connectedDeviceId, serviceUuid, writeUuid, value, BleOutputProperty.withResponse);
      } catch (e) {
        debugPrint('Error writing characteristic: $e');
        continue;
      }
      break;
    }
  }

  @override
  void showDevicesDialog(BuildContext context) {
    startScan();
    final currentContext = context;
    showDialog(
      context: currentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('BLE Devices').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<BleDevice>>(
              stream: BleManager.scanResultsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error occurred').tr());
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('No devices found').tr());
                } else {
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(snapshot.data![index].name ?? 'Unknown').tr(),
                        subtitle: Text('ID: ${snapshot.data![index].deviceId}\nRSSI: ${snapshot.data![index].rssi}'),
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
              child: const Text('Close').tr(),
            ),
          ],
        );
      },
    );
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    if (!isDeviceConnected()) return;
    TextEditingController controller = TextEditingController(text: currentName);
    String? errorMessage;
    final currentContext = context;
    showDialog(
      context: currentContext,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Rename Device').tr(),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'Enter new name'.tr(),
                      errorText: errorMessage,
                    ),
                    onChanged: (text) {
                      if (text.length > 20) {
                        setState(() {
                          errorMessage = 'Device name too long'.tr();
                        });
                        controller.text = text.substring(0, 20);
                      } else if (!RegExp(r'^[\x00-\x7F]+$').hasMatch(text)) {
                        setState(() {
                          errorMessage = 'Only ASCII characters are allowed'.tr();
                        });
                        controller.text = text.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
                      } else {
                        setState(() {
                          errorMessage = null;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel').tr(),
                ),
                TextButton(
                  onPressed: () async {
                    if (controller.text.isEmpty) {
                      setState(() {
                        errorMessage = 'Device name cannot be empty'.tr();
                      });
                      controller.text = 'DALInspector_${connectedDeviceId.substring(connectedDeviceId.length - 6)}';
                      return;
                    } else if (controller.text.length > 20 || !RegExp(r'^[\x00-\x7F]+$').hasMatch(controller.text)) {
                      return;
                    }
                    final prefs = await SharedPreferences.getInstance();
                    prefs.setString('deviceName', controller.text);
                    send(Uint8List.fromList('AT+NAME=${controller.text}\r\n'.codeUnits));
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK').tr(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void onReceived(void Function(Uint8List) onData) {
    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {
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
}