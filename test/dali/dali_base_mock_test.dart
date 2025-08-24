import 'package:dalimaster/connection/manager.dart';
import 'package:dalimaster/connection/mock.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectionManager mgr;
  late MockConnection conn;
  late DaliBase dali;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sendDelays': 0,
      'queryDelays': 0,
      'extDelays': 0,
      'invalidFrameTolerance': 0,
      'dimmingCurve': 'linear',
      'connectionMethod': 'MOCK',
    });
    mgr = ConnectionManager.instance;
    await mgr.useMock();
    expect(mgr.connection is MockConnection, true);
    conn = mgr.connection as MockConnection;
    conn.autoSimulateQueries = true; // 让查询由模拟总线自动响应

    dali = DaliBase(mgr);
    dali.isSingle = true; // 使用新协议帧 0x10/0x11/0x12

    // 给前 8 个设备分配短地址与一些默认状态
    for (var i = 0; i < 8; i++) {
      conn.bus.devices[i].shortAddress = i;
      conn.bus.devices[i].brightness = 0;
      conn.bus.devices[i].groupBits = 0;
      conn.bus.devices[i].scenes.fillRange(0, 16, 0);
      conn.bus.devices[i].lampFailureFlag = false;
      conn.bus.devices[i].limitErrorFlag = false;
      conn.bus.devices[i].resetStateFlag = false;
      conn.bus.devices[i].psFaultFlag = false;
    }
  });

  group('direct arc and broadcast/group', () {
    test('setBright individual/group/broadcast', () async {
      // individual
      await dali.setBright(0, 120);
      expect(conn.bus.deviceByShortAddr(0)!.brightness, 120);

      // add device 0 and 2 into group#1
      conn.bus.deviceByShortAddr(0)!.groupBits |= (1 << 1);
      conn.bus.deviceByShortAddr(2)!.groupBits |= (1 << 1);

      // group direct arc: 使用 groupToAddr 作为 DEC 地址
      final g1 = dali.groupToAddr(1); // 64+1
      await dali.setBright(g1, 33);
      expect(conn.bus.deviceByShortAddr(0)!.brightness, 33);
      expect(conn.bus.deviceByShortAddr(2)!.brightness, 33);
      // 其他设备不受影响
      expect(conn.bus.deviceByShortAddr(1)!.brightness != 33, true);

      // broadcast direct arc: DEC 127 -> even 0xFE
      await dali.setBright(127, 77);
      for (var i = 0; i < 8; i++) {
        expect(conn.bus.deviceByShortAddr(i)!.brightness, 77);
      }

      // clamp
      await dali.setBright(0, 300);
      expect(conn.bus.deviceByShortAddr(0)!.brightness, 254);

      // percentage helper (100% -> 254)
      await dali.setBrightPercentage(1, 100);
      expect(conn.bus.deviceByShortAddr(1)!.brightness, 254);
    });
  });

  group('scenes and groups via API', () {
    test('storeScene and recall via toScene', () async {
      // 设备0: 设置当前亮度->DTR，再存为场景2
      await dali.setDTR(88);
      await dali.storeDTRAsSceneBright(0, 2);
      // 现在调用场景2
      await dali.toScene(0, 2);
      expect(conn.bus.deviceByShortAddr(0)!.brightness, 88);
    });

    test('add/remove group and setGroup high-level', () async {
      // 初始 groupBits 为 0
      expect(conn.bus.deviceByShortAddr(0)!.groupBits, 0);

      // setGroup 会先读取 C1/C0，再逐位 add/remove
      await dali.setGroup(0, (1 << 1) | (1 << 5));
      expect(conn.bus.deviceByShortAddr(0)!.groupBits, (1 << 1) | (1 << 5));

      // 再变更为仅 bit5 保留
      await dali.setGroup(0, (1 << 5));
      expect(conn.bus.deviceByShortAddr(0)!.groupBits, (1 << 5));

      // 直接调用 add/remove API
      await dali.addToGroup(1, 3);
      await dali.removeFromGroup(1, 3);
      expect(conn.bus.deviceByShortAddr(1)!.groupBits & (1 << 3), 0);
    });
  });

  group('status and queries', () {
    test('status bits and device info', () async {
      // 让设备2亮度>0 以便 lampPowerOn 返回 true
      await dali.setBright(2, 10);
      expect(await dali.getControlGearPresent(2), true);
      expect(await dali.getLampPowerOnStatus(2), true);

      // 设置 lampFailure/limitError 标志后查询
      conn.bus.deviceByShortAddr(2)!.lampFailureFlag = true;
      conn.bus.deviceByShortAddr(2)!.limitErrorFlag = true;
      expect(await dali.getLampFailureStatus(2), true);
      expect(await dali.getLimitError(2), true);

      // 基本字段查询
      expect(await dali.getBright(2), 10);

      // 设备信息（使用缺省值）
      final t = await dali.getDeviceType(2);
      final et = await dali.getDeviceExtType(2);
      final ver = await dali.getDeviceVersion(2);
      expect(t >= 0 && t <= 255, true);
      expect(et >= 0 && et <= 255, true);
      expect(ver >= 0 && ver <= 255, true);
    });

    test('DTR get/set utilities', () async {
      await dali.setDTR(0x22);
      expect(await dali.getDTR(0), 0x22);

      await dali.setDTR1(0x33);
      expect(await dali.getDTR1(0), 0x33);

      await dali.setDTR2(0x44);
      expect(await dali.getDTR2(0), 0x44);

      await dali.setPowerOnLevel(3, 12);
      expect(conn.bus.deviceByShortAddr(3)!.powerOnLevel, 12);

      await dali.setSystemFailureLevel(3, 13);
      expect(conn.bus.deviceByShortAddr(3)!.systemFailureLevel, 13);

      await dali.setMinLevel(3, 1);
      expect(conn.bus.deviceByShortAddr(3)!.minLevel, 1);

      await dali.setMaxLevel(3, 200);
      expect(conn.bus.deviceByShortAddr(3)!.maxLevel, 200);

      await dali.setFadeTime(3, 15);
      expect(conn.bus.deviceByShortAddr(3)!.fadeTime, 15);

      await dali.setFadeRate(3, 16);
      expect(conn.bus.deviceByShortAddr(3)!.fadeRate, 16);

      // 读取组合的渐变参数（mock 下 0xA5 返回 physicalMinLevel，默认 0）
      final rs = await dali.getGradualChange(3);
      expect(rs.length, 2);
    });
  });

  group('address allocation flow (randomise/compare/program/withdraw)', () {
    test('randomise, compareAddress, programShortAddr, withdraw', () async {
      // 清除前 8 个设备短地址用于分配
      for (var i = 0; i < 8; i++) {
        conn.bus.devices[i].shortAddress = null;
        conn.bus.devices[i].isolated = false;
      }

      await dali.initialiseAll();
      await dali.randomise();

      // 选择范围：将 H/M/L 寄存器设置为较大值以命中至少一个设备
      await dali.queryAddressH(0xFF);
      await dali.queryAddressM(0xFF);
      await dali.queryAddressL(0xFF);

      // 在 mock 中，compareAddress 会基于 anyCompareMatch 返回响应
      final matched = await dali.compareAddress();
      expect(matched, true);

      // 给命中的设备编程短地址 4
      await dali.programShortAddr(4);

      // withdraw 隔离刚编程设备
      await dali.withdraw();

      // 断言：至少有一个设备拥有短地址 4 且被隔离
      final d = conn.bus.deviceByShortAddr(4);
      expect(d != null, true);
      expect(d!.isolated, true);

      // queryShortAddr() 返回最近编程的短地址
      final sa = await dali.queryShortAddr();
      expect(sa, 4);

      // verifyShortAddr(4) 成功
      final ok = await dali.verifyShortAddr(4);
      expect(ok, true);

      // 取消隔离
      await dali.cancel();
      expect(conn.bus.devices.any((e) => e.isolated), false);
    });
  });
}
