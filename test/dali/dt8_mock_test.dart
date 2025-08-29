import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dalimaster/connection/manager.dart';
import 'package:dalimaster/connection/mock.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:dalimaster/dali/dt8.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectionManager mgr;
  late MockConnection conn;
  late DaliBase base;
  late DaliDT8 dt8;

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
    conn = mgr.connection as MockConnection;
    conn.autoSimulateQueries = true;

    base = DaliBase(mgr)..isSingle = true;
    dt8 = DaliDT8(base);

    // Prepare device 0
    for (var i = 0; i < 4; i++) {
      conn.bus.devices[i].shortAddress = i;
    }
    final d0 = conn.bus.deviceByShortAddr(0)!;
    // deterministic state
    d0.activeColorMode = 'ct';
    d0.colorType = 0x20; // ct capable
    d0.mirek = 250; // 4000K
    d0.mirekMin = 153;
    d0.mirekMax = 370;
    d0.xyX = 20000;
    d0.xyY = 25000;
    d0.rgbwafChannels.setAll(0, [10, 20, 30, 40, 50, 60]);
    d0.primaryN.setAll(0, [1, 2, 3, 4, 5, 6]);
  });

  group('DT8 report/basic queries', () {
    test('report x/y/mirek and min/max', () async {
      final xy = await dt8.getReportColour(0);
      expect(xy[0], closeTo(20000 / 65535.0, 1e-6));
      expect(xy[1], closeTo(25000 / 65535.0, 1e-6));

      final ct = await dt8.getReportColorTemperature(0);
      expect(ct, closeTo(1e6 ~/ 250, 1));

      final minCt = await dt8.getMinColorTemperature(0);
      final maxCt = await dt8.getMaxColorTemperature(0);
      expect(minCt, closeTo(1e6 ~/ 153, 1));
      expect(maxCt, closeTo(1e6 ~/ 370, 1));
    });

    test('primaryN info and count', () async {
      // NUMBER OF PRIMARIES
      final n = await dt8.getNumberOfPrimaries(0);
      expect(n, 3);
      // PRIMARY#0 x/y/type (mock synthesized values by selector)
      final x0 = await dt8.getPrimaryXRaw(0, 0);
      final y0 = await dt8.getPrimaryYRaw(0, 0);
      final t0 = await dt8.getPrimaryTy(0, 0);
      expect(x0, isNotNull);
      expect(y0, isNotNull);
      expect(t0, isNotNull);
    });

    test('RGBWAF and primaries dim levels', () async {
      expect(await dt8.getRedDimLevel(0), 10);
      expect(await dt8.getGreenDimLevel(0), 20);
      expect(await dt8.getBlueDimLevel(0), 30);
      expect(await dt8.getWhiteDimLevel(0), 40);
      expect(await dt8.getAmberDimLevel(0), 50);
      expect(await dt8.getFreecolourDimLevel(0), 60);

      expect(await dt8.getPrimaryDimLevel(0, 0), 1);
      expect(await dt8.getPrimaryDimLevel(0, 1), 2);
      expect(await dt8.getPrimaryDimLevel(0, 2), 3);
    });
  });

  group('DT8 temporary via copyReportColourToTemp', () {
    test('copy and read temporary snapshot', () async {
      // Act: copy report -> temp
      await base.copyReportColourToTemp(0);

      final xyT = await dt8.getTemporaryColour(0);
      expect(xyT[0], closeTo(20000 / 65535.0, 1e-6));
      expect(xyT[1], closeTo(25000 / 65535.0, 1e-6));

      final ctT = await dt8.getTemporaryColorTemperature(0);
      expect(ctT, closeTo(1e6 ~/ 250, 1));

      expect(await dt8.getTemporaryRedDimLevel(0), 10);
      expect(await dt8.getTemporaryGreenDimLevel(0), 20);
      expect(await dt8.getTemporaryBlueDimLevel(0), 30);
      expect(await dt8.getTemporaryWhiteDimLevel(0), 40);
      expect(await dt8.getTemporaryAmberDimLevel(0), 50);
      expect(await dt8.getTemporaryFreecolourDimLevel(0), 60);

      final ctType = await dt8.getTemporaryColourType(0);
      expect(ctType, 0x20);
    });
  });
}
