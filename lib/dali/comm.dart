import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/connection/manager.dart';
import '/connection/connection.dart';

class DaliComm {
  final ConnectionManager manager;
  late int sendDelays;
  late int queryDelays;
  late int extDelays;

  DaliComm(this.manager) {
    _loadDelays();
  }

  Future<void> _loadDelays() async {
    final prefs = await SharedPreferences.getInstance();
    sendDelays = prefs.getInt('sendDelays') ?? 50;
    queryDelays = prefs.getInt('queryDelays') ?? 50;
    extDelays = prefs.getInt('extDelays') ?? 100;
  }

  int gw = 0;
  int com = 0;
  String name = "dali";
  bool isSingle = true;
  bool isNew = false;

  /// DALI data checksum
  List<int> checksum(List<int> data) {
    int sum = 0;
    for (int i = 0; i < data.length; i++) {
      sum += data[i];
    }
    while (sum > 255) {
      sum -= 256;
    }
    data.add(sum);
    return data;
  }

  Future<void> write(List<int> data) async {
    Connection conn = manager.connection;
    debugPrint("dali:write: $data");
    await conn.send(Uint8List.fromList(data));
  }

  Future<Uint8List?> read(int len, {int timeout = 100}) async {
    Connection conn = manager.connection;
    return await conn.read(len, timeout: timeout);
    //return conn.readBuffer;
  }

  Future<int> checkGatewayType(int gateway) async {
    Connection conn = manager.connection;
    List<int> bytes1 = [0x01, 0x00, 0x00]; // USB
    List<int> bytes2 = [0x28, 0x01, gateway, 0x11, 0x00, 0x00, 0xff]; // Legacy
    List<int> bytes3 = [0x28, 0x01, gateway, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]; // New

    await conn.send(Uint8List.fromList(bytes1));
    await Future.delayed(Duration(milliseconds: 100));
    Uint8List? data = await conn.read(2, timeout: 100);
    if (data != null && data.isNotEmpty) {
      if (data[0] > 0) {
        debugPrint("dali:checkGatewayType: USB interface detected");
        return 1; // USB interface
      }
    }
    await conn.send(Uint8List.fromList(bytes2));
    await Future.delayed(Duration(milliseconds: 100));
    data = await conn.read(2, timeout: 100);
    if (data != null && data.length == 2) {
      if (data[0] == gateway && data[1] >= 0) {
        debugPrint("dali:checkGatewayType: Legacy 485 interface detected");
        return 2; // Legacy 485 interface
      }
    }
    await conn.send(Uint8List.fromList(bytes3));
    await Future.delayed(Duration(milliseconds: 100));
    data = await conn.read(2, timeout: 100);
    if (data != null && data.length == 2) {
      if (data[0] == gateway && data[1] >= 0) {
        debugPrint("dali:checkGatewayType: New 485 interface detected");
        return 3; // New 485 interface
      }
    }
    debugPrint("dali:checkGatewayType: No valid gateway detected");
    return 0;
  }

  Future<void> flush() async {
    Connection conn = manager.connection;
    for (int i = 0; i < 10; i++) {
      Uint8List? data = await conn.read(2, timeout: 100);
      if (data == null) {
        break;
      }
    }
  }

  /// DALI reset bus
  Future<void> resetBus() async {
    List<int> buffer = [0x00, 0x00, 0x00];
    write(buffer);
    await Future.delayed(Duration(milliseconds: 100));
    // SERIAL.write(buffer, com);
    await Future.delayed(Duration(milliseconds: 100));
    // SERIAL.closeCOM(com);
  }

  /// send DALI command (not need response)
  Future<void> sendRaw(int a, int b, {int? d, int? g}) async {
    int gwAddr = g ?? gw;
    int delays = d ?? sendDelays;
    int addr = a;
    int cmd = b;
    List<int> command = [0x28, 0x01, gwAddr, 0x12, addr, cmd];
    if (isNew) command.addAll([0x00, 0x00, 0x00]);
    List<int> buffer = checksum(command);
    write(buffer);
    await Future.delayed(Duration(milliseconds: delays));
  }

  Future<void> sendRawNew(int a, int b, {int? d, int? g, bool needVerify = false}) async {
    int delays = d ?? sendDelays;
    int addr = a;
    int cmd = b;
    // Note: new on board transceiver did not need checksum
    List<int> buffer = [0x10, addr, cmd];
    if (addr > 255 || cmd > 255) {
      debugPrint("dali:sendRawNew: address out of range");
      return;
    }
    if (needVerify) {
      buffer[0] = 0x12;
      for (int i = 0; i < 3; i++) {
        //await flush();
        await write(buffer);
        await Future.delayed(Duration(milliseconds: delays));
        Uint8List? data = await read(2, timeout: queryDelays);
        if (data != null && data[0] >= 254) {
          debugPrint("dali:sendRawNew: verify success");
          return;
        } else {
          debugPrint("dali:sendRawNew: verify failed");
          await Future.delayed(Duration(milliseconds: delays));
        }
      }
    } else {
      await write(buffer);
    }
  }

  /// Send DALI extended command, which needs to be sent two times in 100ms.
  Future<void> sendExtRaw(int a, int b, {int? d, int? g}) async {
    int gwAddr = g ?? gw;
    int delays = d ?? extDelays;
    int addr = a;
    int cmd = b;
    List<int> command = [0x28, 0x01, gwAddr, 0x13, addr, cmd];
    List<int> buffer = checksum(command);
    write(buffer);
    await Future.delayed(Duration(milliseconds: delays));
  }

  Future<void> sendExtRawNew(int a, int b, {int? d, int? g}) async {
    int delays = d ?? extDelays;
    int addr = a;
    int cmd = b;
    // Note: original code did not do checksum here
    List<int> buffer = [0x11, addr, cmd];
    await write(buffer);
    await Future.delayed(Duration(milliseconds: delays));
  }

  Future<int> queryRaw(int a, int b, {int? d, int? g}) async {
    int delays = d ?? queryDelays;
    int addr = a;
    int cmd = b;
    List<int> buffer = [0x28, 0x01, gw, 0x14, addr, cmd];
    buffer = checksum(buffer);
    int ret = -2;
    await write(buffer);
    for (int i = 0; i < 10; i++) {
      await Future.delayed(Duration(milliseconds: delays));
      Uint8List? data = await read(5, timeout: delays);
      if (data != null && data.length == 5) {
        final sum = checksum(data.sublist(0, 3))[4];
        if (data[0] == 0x22 && data[2] == gw && data[4] == sum) {
          if (data[1] == 0x03) {
            ret = data[3];
            break;
          } else if (data[1] == 0x04) {
            ret = -1;
            break;
          } else {
            debugPrint("dali:queryRaw: invalid response: $data");
          }
        }
      } else {
        debugPrint("dali:queryRaw: no data or invalid data, length: ${data?.length}");
      }
      await write(buffer);
    }
    return ret;
  }

  /// send DALI command (need response)
  Future<int> queryRawNew(int a, int b, {int? d, int? g}) async {
    int delays = d ?? queryDelays;
    int addr = a;
    int cmd = b;
    List<int> buffer = [0x12, addr, cmd];
    int ret = -2;
    //await flush();
    await write(buffer);
    for (int i = 0; i < 10; i++) {
      await Future.delayed(Duration(milliseconds: delays));
      Uint8List? data = await read(2, timeout: delays);
      if (data != null && data.length == 2) {
        if (data[0] == 255) {
          ret = data[1];
          break;
        } else if (data[0] == 254) {
          ret = -1;
          break;
        }
      } else {
        debugPrint("dali:queryRawNew: no data");
      }
      await write(buffer);
    }

    return ret;
  }

  /// Send HEX command
  Future<void> sendCmd(int addr, int c, {int? t, int? d, int? g}) async {
    int times = t ?? 1;
    for (int i = 0; i < times; i++) {
      if (isSingle) {
        await sendRawNew(addr, c, d: d, g: g);
      } else {
        await sendRaw(addr, c, d: d, g: g);
      }
    }
  }

  /// Send HEX request, and return the response
  Future<int> queryCmd(int addr, int c, {int? d, int? g}) async {
    if (isSingle) {
      int ret = await queryRawNew(addr, c, d: d, g: g);
      return ret;
    }
    int ret = await queryRaw(addr, c, d: d, g: g);
    return ret;
  }

  /// Send command with DEC address
  Future<void> send(int a, int c, {int? t, int? d, int? g}) async {
    int addr = a * 2 + 1;
    await sendCmd(addr, c, t: t, d: d, g: g);
  }

  /// Send request with DEC address, and return the response
  Future<int> query(int a, int c, {int? d, int? g}) async {
    int addr = a * 2 + 1;
    int resp = await queryCmd(addr, c, d: d, g: g);
    return resp;
  }

  /// convert brightness to percent curve
  int brightnessToLog(int brightness) {
    return (log(brightness + 1) / log(256) * 255).toInt();
  }

  int logToBrightness(int logValue) {
    return (pow(10, logValue * log(256) / log(10)) - 1).toInt();
  }

  /// getBusStatus
  Future<bool> getBusStatus() async {
    // SERIAL.write([0x01, 0x00, 0x00], com);
    await Future.delayed(Duration(milliseconds: 50));
    // Suppose we got no valid data => no response
    return false;
  }

  /// Send brightness with DEC address
  Future<void> setBright(int a, int b, {int? t, int? d, int? g}) async {
    final prefs = await SharedPreferences.getInstance();
    String curve = prefs.getString('dimmingCurve') ?? 'Linear';
    int addr = a * 2;
    int bright = b;
    if (curve == 'Logarithmic') {
      bright = brightnessToLog(b);
      //brightInt = (bright * 254).floor();
    }
    if (b > 254) {
      b = 254;
    }
    await sendCmd(addr, bright, t: t, d: d, g: g);
  }

  /// Send brightness % with DEC address
  Future<void> setBrightPercentage(int a, double b, {int? t, int? d, int? g}) async {
    int bright = (b * 254 / 100).floor();
    if (bright > 254) {
      bright = 254;
    }
    await setBright(a, bright, t: t, d: d, g: g);
  }
}
