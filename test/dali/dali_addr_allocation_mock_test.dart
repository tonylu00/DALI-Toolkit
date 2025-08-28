import 'package:dalimaster/connection/manager.dart';
import 'package:dalimaster/connection/mock.dart';
import 'package:dalimaster/dali/addr.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectionManager mgr;
  late MockConnection conn;
  late DaliBase base;
  late DaliAddr addr;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sendDelays': 0,
      'queryDelays': 0,
      'extDelays': 0,
      'invalidFrameTolerance': 0,
      'dimmingCurve': 'linear',
      'connectionMethod': 'MOCK',
      'removeAddr': false,
      'closeLight': false,
    });
    mgr = ConnectionManager.instance;
    await mgr.useMock();
    conn = mgr.connection as MockConnection;
    conn.autoSimulateQueries = true; // 让查询自动响应

    base = DaliBase(mgr);
    base.isSingle = true;
    addr = DaliAddr(base);
  });

  void isolateAllExceptFirstN(int n) {
    for (var i = n; i < conn.bus.devices.length; i++) {
      conn.bus.devices[i].isolated = true;
    }
  }

  group('allocate-all 16 devices with compareMulti acceleration', () {
    test('full flow assigns at least 16 SAs', () async {
      // 清空设备状态（前 64 个）
      for (final d in conn.bus.devices) {
        d.shortAddress = null;
        d.isolated = false;
        d.groupBits = 0;
        d.scenes.fillRange(0, 16, 0);
        d.brightness = 0;
        d.randH = 0xFF;
        d.randM = 0xFF;
        d.randL = 0xFF;
      }
      // 构造三个连续块，总数 >= 16
      // 块1: 6 台, H=0x40 M=0x10 L=10..15
      for (var i = 0; i < 12; i++) {
        final d = conn.bus.devices[i];
        d.randH = 0x40;
        d.randM = 0x10;
        d.randL = 10 + i;
      }
      // 块2: 5 台, H=0x40 M=0x22 L=50..54
      for (var i = 0; i < 12; i++) {
        final d = conn.bus.devices[i];
        d.randH = 0x40;
        d.randM = 0x22;
        d.randL = 50 + i;
      }
      // 块3: 5 台, H=0x40 M=0x33 L=100..104
      for (var i = 0; i < 16; i++) {
        final d = conn.bus.devices[i];
        d.randH = 0x40;
        d.randM = 0x33;
        d.randL = 100 + i;
      }
      // 其余设备隔离，避免干扰
      isolateAllExceptFirstN(16);

      addr.isAllocAddr = true;

      await addr.resetAndAllocAddr();

      // 断言: 至少 16 台分配了短地址（统计前 63 台设备是否获得短地址）
      int assigned = 0;
      for (var i = 0; i < 63; i++) {
        if (conn.bus.devices[i].shortAddress != null) assigned++;
      }
      expect(assigned == 16, true, reason: 'allocated short addresses: $assigned');
      addr.isAllocAddr = false;
    });
  });

  group('compareMulti accelerates contiguous block', () {
    test('programs multiple SAs across iterations', () async {
      // 清空设备状态（前 64 个）
      for (final d in conn.bus.devices) {
        d.shortAddress = null;
        d.isolated = false;
        d.groupBits = 0;
        d.scenes.fillRange(0, 16, 0);
        d.brightness = 0;
        d.randH = 0xFF;
        d.randM = 0xFF;
        d.randL = 0xFF;
      }
      // 仅使用前 8 台，构造同 H/M、连续 L 的块
      for (var i = 0; i < 8; i++) {
        final d = conn.bus.devices[i];
        d.shortAddress = null;
        d.isolated = false;
        d.randH = 0x55;
        d.randM = 0x66;
        d.randL = 20 + i; // 20..27 连续
      }
      // 其余隔离
      //_isolateAllExceptFirstN(8);

      addr.isAllocAddr = true;

      // 直接以已知 H/M/L 起点调用 compareMulti
      int ad = 0;
      ad = await addr.compareMulti(0x55, 0x66, 20, ad); // 从 20 开始

      int assigned = 0;
      for (var i = 0; i < 63; i++) {
        if (conn.bus.devices[i].shortAddress != null) assigned++;
      }

      // 应当分配 8 台（不考虑可能存在验证失败的情况）
      expect(assigned == 8, true,
          reason: 'compareMulti did not accelerate enough, assigned=$assigned');

      addr.isAllocAddr = false;
    });
  });
}
