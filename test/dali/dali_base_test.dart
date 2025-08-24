import 'dart:typed_data';

import 'package:dalimaster/connection/connection.dart';
import 'package:dalimaster/connection/manager.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestConnection implements Connection {
  final List<Uint8List> sent = [];
  final List<Uint8List> _responses = [];
  void enqueueResponse(List<int> bytes) => _responses.add(Uint8List.fromList(bytes));

  @override
  Future<void> connect(String address, {int port = 0}) async {}

  @override
  void disconnect() {}

  @override
  Uint8List? readBuffer;

  @override
  Future<Uint8List?> read(int length, {int timeout = 100}) async {
    if (_responses.isEmpty) return null;
    return _responses.removeAt(0);
  }

  @override
  Future<void> send(Uint8List data) async {
    sent.add(Uint8List.fromList(data));
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {}

  @override
  Future<void> startScan() async {}

  @override
  void stopScan() {}

  @override
  bool isDeviceConnected() => true;

  @override
  void openDeviceSelection(BuildContext context) {}

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {}

  @override
  String get connectedDeviceId => 'TEST';

  @override
  String get type => 'MOCK';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ConnectionManager mgr;
  late TestConnection conn;
  late DaliBase dali;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sendDelays': 0,
      'queryDelays': 0,
      'extDelays': 0,
      'invalidFrameTolerance': 0,
      'dimmingCurve': 'linear',
    });
    mgr = ConnectionManager.instance;
    // 先切到 Mock，避免断开 BLE 时触发平台通道
    await mgr.useMock();
    conn = TestConnection();
    mgr.replaceConnection(conn);
    // 强制单总线模式
    dali = DaliBase(mgr);
    dali.isSingle = true;
  });

  tearDown(() async {
    // 清理已发送
    conn.sent.clear();
  });

  List<int> lastSent() => conn.sent.isNotEmpty ? conn.sent.last : [];

  group('basic send', () {
    test('toScene', () async {
      await dali.toScene(3, 7);
      expect(lastSent(), [0x10, 3 * 2 + 1, 16 + 7]);
    });

    test('reset/off/on/recallMin/Max', () async {
      await dali.reset(5);
      expect(lastSent(), [0x10, 5 * 2 + 1, 0x20]);

      await dali.off(1);
      expect(lastSent(), [0x10, 1 * 2 + 1, 0x00]);

      await dali.on(1);
      expect(lastSent(), [0x10, 1 * 2 + 1, 0x05]);

      await dali.recallMaxLevel(2);
      expect(lastSent(), [0x10, 2 * 2 + 1, 0x05]);

      await dali.recallMinLevel(2);
      expect(lastSent(), [0x10, 2 * 2 + 1, 0x06]);
    });

    test('groupToAddr', () {
      expect(dali.groupToAddr(0), 64);
      expect(dali.groupToAddr(15), 79);
    });

    test('sendExtCmd', () async {
      await dali.sendExtCmd(0xAA, 0xBB);
      expect(lastSent(), [0x11, 0xAA, 0xBB]);
    });
  });

  group('DTR and colour write', () {
    test('setDTR variants', () async {
      await dali.setDTR(0x12);
      expect(lastSent(), [0x10, 0xA3, 0x12]);
      await dali.setDTR1(0x34);
      expect(lastSent(), [0x10, 0xC3, 0x34]);
      await dali.setDTR2(0x56);
      expect(lastSent(), [0x10, 0xC5, 0x56]);
    });

    test('storeDTRAs*', () async {
      await dali.storeDTRAsFadeTime(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2e]);
      await dali.storeDTRAsFadeRate(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2f]);
      await dali.storeDTRAsPoweredBright(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2d]);
      await dali.storeDTRAsSystemFailureLevel(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2c]);
      await dali.storeDTRAsMinLevel(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2b]);
      await dali.storeDTRAsMaxLevel(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2a]);
      await dali.storeColourTempLimits(1);
      expect(lastSent(), [0x11, 1 * 2 + 1, 0xF2]);
    });

    test('colour DT8 helpers', () async {
      await dali.activate(2);
      expect(lastSent(), [0x10, 2 * 2 + 1, 0xE2]);
      await dali.setDTRAsColourX(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xE0]);
      await dali.setDTRAsColourY(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xE1]);
      await dali.setDTRAsColourRGB(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xE2]);
      await dali.setDTRAsColourTemp(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xE7]);
      await dali.copyReportColourToTemp(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xEE]);
      await dali.queryColourValue(2);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0xFA]);
    });
  });

  group('queries', () {
    test('getOnlineStatus true/false', () async {
      // true => gateway returns [255,255]
      conn.enqueueResponse([255, 255]);
      expect(await dali.getOnlineStatus(1), true);
      // false => DaliDeviceNoResponseException -> false
      // emulate: gateway returns [254,0]
      conn.enqueueResponse([254, 0]);
      expect(await dali.getOnlineStatus(1), false);
    });

    test('getBright default and actual', () async {
      // actual value 100
      conn.enqueueResponse([255, 100]);
      expect(await dali.getBright(1), 100);
      // unknown 255 -> return 254
      conn.enqueueResponse([255, 255]);
      expect(await dali.getBright(1), 254);
    });

    test('device info queries', () async {
      conn.enqueueResponse([255, 0x20]);
      expect(await dali.getDeviceType(1), 0x20);
      conn.enqueueResponse([255, 0x31]);
      expect(await dali.getDeviceExtType(1), 0x31);
      conn.enqueueResponse([255, 0x12]);
      expect(await dali.getDeviceVersion(1), 0x12);
    });

    test('DTR reads', () async {
      conn.enqueueResponse([255, 0x01]);
      expect(await dali.getDTR(1), 0x01);
      conn.enqueueResponse([255, 0x02]);
      expect(await dali.getDTR1(1), 0x02);
      conn.enqueueResponse([255, 0x03]);
      expect(await dali.getDTR2(1), 0x03);
    });

    test('group and scenes', () async {
      conn.enqueueResponse([255, 0xAA]);
      expect(await dali.getGroupH(1), 0xAA);
      conn.enqueueResponse([255, 0xBB]);
      expect(await dali.getGroupL(1), 0xBB);
      // getGroup combines
      // Need two more responses for H/L
      conn.enqueueResponse([255, 0xAA]);
      conn.enqueueResponse([255, 0xBB]);
      expect(await dali.getGroup(1), 0xAA * 256 + 0xBB);

      // getScene index 5 -> command 0xB0 + 5
      conn.enqueueResponse([255, 123]);
      expect(await dali.getScene(1, 5), 123);
    });

    test('status bits', () async {
      conn.enqueueResponse([255, 0x5A]);
      expect(await dali.getStatus(1), 0x5A);
      conn.enqueueResponse([255, 255]);
      expect(await dali.getControlGearPresent(1), true);
      conn.enqueueResponse([255, 255]);
      expect(await dali.getLampFailureStatus(1), true);
      conn.enqueueResponse([255, 0]);
      expect(await dali.getLampPowerOnStatus(1), false);
      conn.enqueueResponse([255, 255]);
      expect(await dali.getLimitError(1), true);
      conn.enqueueResponse([255, 0]);
      expect(await dali.getResetStatus(1), false);
      conn.enqueueResponse([255, 255]);
      expect(await dali.getMissingShortAddress(1), true);
    });

    test('random address queries', () async {
      conn.enqueueResponse([255, 0x11]);
      expect(await dali.getRandomAddrH(1), 0x11);
      conn.enqueueResponse([255, 0x22]);
      expect(await dali.getRandomAddrM(1), 0x22);
      conn.enqueueResponse([255, 0x33]);
      expect(await dali.getRandomAddrL(1), 0x33);
    });
  });

  group('programming & compare', () {
    test('storeDTRAsAddr/programShortAddr/query/verify', () async {
      await dali.storeDTRAsAddr(3);
      expect(lastSent(), [0x11, 3 * 2 + 1, 0x80]);

      await dali.programShortAddr(4);
      expect(lastSent(), [0x10, 0xB7, 4 * 2 + 1]);

      conn.enqueueResponse([255, 4 * 2 + 1]);
      expect(await dali.queryShortAddr(), 4);

      // verify true: any response (255, X) means success
      conn.enqueueResponse([255, 0]);
      expect(await dali.verifyShortAddr(4), true);

      // verify false: 254 indicates no response
      conn.enqueueResponse([254, 0]);
      expect(await dali.verifyShortAddr(5), false);
    });

    test('compareAddress sequence', () async {
      await dali.queryAddressL(0x12);
      await dali.queryAddressM(0x34);
      await dali.queryAddressH(0x56);
      // The compareAddress queries 0xA9 at addr 0x01 (cmd mode)
      conn.enqueueResponse([255, 1]);
      expect(await dali.compareAddress(), true);

      // compare(h,m,l)
      await dali.queryAddressL(0x11);
      await dali.queryAddressM(0x22);
      await dali.queryAddressH(0x33);
      // DeviceNoResponse => false
      conn.enqueueResponse([254, 0]);
      expect(await dali.compare(0x33, 0x22, 0x11), false);
    });
  });

  group('gradual/power/limits', () {
    test('setGradualChange*', () async {
      await dali.setGradualChangeSpeed(2, 7);
      // setDTR then storeDTRAsFadeTime
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 7]));
      expect(lastSent(), [0x11, 2 * 2 + 1, 0x2e]);

      await dali.setGradualChangeRate(2, 8);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 8]));
      expect(lastSent(), [0x11, 2 * 2 + 1, 0x2f]);
    });

    test('getGradualChange breakdown', () async {
      // query 0xA5 returns e.g., 0x1FF simulated by two reads: but queryRawNew returns single byte
      // emulate 300 -> will be received as 300%256=44, but our API expects single byte.
      conn.enqueueResponse([255, 44]);
      final rs = await dali.getGradualChange(1);
      expect(rs, [44, 0]);
    });

    test('power/system/min/max/physical/fade', () async {
      await dali.setPowerOnLevel(1, 10);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 10]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2d]);

      conn.enqueueResponse([255, 10]);
      expect(await dali.getPowerOnLevel(1), 10);

      await dali.setSystemFailureLevel(1, 11);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 11]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2c]);

      conn.enqueueResponse([255, 11]);
      expect(await dali.getSystemFailureLevel(1), 11);

      await dali.setMinLevel(1, 12);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 12]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2b]);
      conn.enqueueResponse([255, 12]);
      expect(await dali.getMinLevel(1), 12);

      await dali.setMaxLevel(1, 13);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 13]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2a]);
      conn.enqueueResponse([255, 13]);
      expect(await dali.getMaxLevel(1), 13);

      await dali.setPhysicalMinLevel(1, 14);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 14]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2b]);
      conn.enqueueResponse([255, 14]);
      expect(await dali.getPhysicalMinLevel(1), 14);

      await dali.setFadeTime(1, 15);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 15]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2e]);
      conn.enqueueResponse([255, 15]);
      expect(await dali.getFadeTime(1), 15);

      await dali.setFadeRate(1, 16);
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x10, 0xA3, 16]));
      expect(lastSent(), [0x11, 1 * 2 + 1, 0x2f]);
      conn.enqueueResponse([255, 16]);
      expect(await dali.getFadeRate(1), 16);
    });
  });

  group('group & scenes helpers', () {
    test('add/remove group and setGroup', () async {
      await dali.addToGroup(2, 5);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0x60 + 5]);
      await dali.removeFromGroup(2, 5);
      expect(lastSent(), [0x11, 2 * 2 + 1, 0x70 + 5]);

      // setGroup with equal value should early return (no send).
      // Mock getGroup to return X: emulate via responses for getGroupH/L
      conn.enqueueResponse([255, 0x00]);
      conn.enqueueResponse([255, 0x03]);
      // value 0x0003 equals -> no change
      final before = conn.sent.length;
      await dali.setGroup(1, 0x0003);
      // setGroup 会产生两次查询（C1/C0），但不应产生写入 0x60/0x70 指令
      expect(conn.sent.length, before + 2);
      final q1 = conn.sent[before + 0];
      final q2 = conn.sent[before + 1];
      expect(q1[0], 0x12);
      expect(q1[1], 1 * 2 + 1);
      expect(q1[2], anyOf(0xC1, 0xC0));
      expect(q2[0], 0x12);
      expect(q2[1], 1 * 2 + 1);
      expect(q2[2], anyOf(0xC1, 0xC0));

      // Change some bits: getGroup throws to force write path
      // emulate: first getGroupH fails -> device no response
      // query for getGroupH
      conn.enqueueResponse([254, 0]);
      final before2 = conn.sent.length;
      await dali.setGroup(1, 1 << 0); // only bit0 set
      // Either add or remove, check that at least one 0x11 frame with correct addr is sent
      final writes = conn.sent.skip(before2).where((e) => e[0] == 0x11 && e[1] == 1 * 2 + 1);
      expect(writes.any((e) => e[2] == 0x60 || e[2] == 0x60 + 0), true);
    });

    test('scenes helpers', () async {
      await dali.storeScene(3, 9);
      // storeScene will call copyCurrentBrightToDTR then storeDTRAsSceneBright
      expect(conn.sent[conn.sent.length - 2], Uint8List.fromList([0x11, 3 * 2 + 1, 0x21]));
      expect(lastSent(), [0x11, 3 * 2 + 1, 64 + 9]);

      // removeScene
      await dali.removeScene(4, 7);
      expect(lastSent(), [0x11, 4 * 2 + 1, 0x50 + 7]);

      // getScenes triggers 16 queries
      for (int i = 0; i < 16; i++) {
        conn.enqueueResponse([255, i]);
      }
      final map = await dali.getScenes(1);
      expect(map.length, 16);
      expect(map[0], 0);
      expect(map[15], 15);
    });
  });

  group('bus ctrl & address allocation', () {
    test('terminate/randomise/initialise/withdraw/cancel/physical/addr regs', () async {
      await dali.terminate();
      expect(lastSent(), [0x10, 0xA1, 0x00]);

      await dali.randomise();
      expect(lastSent(), [0x11, 0xA7, 0x00]);

      await dali.initialiseAll();
      expect(lastSent(), [0x11, 0xA5, 0x00]);

      await dali.initialise();
      expect(lastSent(), [0x11, 0xA5, 0xFF]);

      await dali.withdraw();
      expect(lastSent(), [0x10, 0xAB, 0x00]);

      await dali.cancel();
      expect(lastSent(), [0x10, 0xAD, 0x00]);

      await dali.physicalSelection();
      expect(lastSent(), [0x10, 0xBD, 0x00]);

      await dali.queryAddressH(0x12);
      expect(lastSent(), [0x10, 0xB1, 0x12]);
      await dali.queryAddressM(0x34);
      expect(lastSent(), [0x10, 0xB3, 0x34]);
      await dali.queryAddressL(0x56);
      expect(lastSent(), [0x10, 0xB5, 0x56]);
    });
  });

  group('brightness send', () {
    test('setBright clamp & percentage', () async {
      await dali.setBright(2, 300); // clamp to 254
      expect(lastSent(), [0x10, 2 * 2, 254]);

      await dali.setBrightPercentage(2, 100);
      expect(lastSent(), [0x10, 2 * 2, 254]);
    });
  });
}
