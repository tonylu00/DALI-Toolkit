import 'package:dalimaster/dali/addr.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:dalimaster/connection/manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestDaliBase extends DaliBase {
  TestDaliBase() : super(ConnectionManager.instance) {
    // 避免任何真实 IO
    isSingle = true;
  }

  final calls = <String>[]; // 记录调用
  final online = <int, bool>{}; // 短地址是否在线
  // 比较寄存器与行为
  int selH = 0, selM = 0, selL = 0;
  bool compareResult = false;
  // 编程/查询短地址
  int programmedShortAddr = -1;
  int queryShortAddrValue = -1;
  int nextQueryValue = 0;
  final sentFrames = <List<int>>[];

  // 覆盖必要方法
  @override
  Future<void> setDTR(int value) async => calls.add('setDTR:$value');

  @override
  Future<void> storeDTRAsAddr(int a) async => calls.add('storeDTRAsAddr:$a');

  @override
  Future<void> off(int a, {int? t, int? d, int? g}) async => calls.add('off:$a');

  @override
  Future<void> terminate() async => calls.add('terminate');

  @override
  Future<void> initialiseAll() async => calls.add('initialiseAll');

  @override
  Future<void> initialise() async => calls.add('initialise');

  @override
  Future<void> randomise() async => calls.add('randomise');

  @override
  Future<void> withdraw() async => calls.add('withdraw');

  @override
  Future<void> programShortAddr(int a) async {
    calls.add('programShortAddr:$a');
    programmedShortAddr = a;
  }

  @override
  Future<int> queryShortAddr() async => queryShortAddrValue;

  @override
  Future<bool> getOnlineStatus(int a) async => online[a] == true;

  @override
  Future<void> queryAddressH(int addr) async {
    selH = addr;
    calls.add('selH:$addr');
  }

  @override
  Future<void> queryAddressM(int addr) async {
    selM = addr;
    calls.add('selM:$addr');
  }

  @override
  Future<void> queryAddressL(int addr) async {
    selL = addr;
    calls.add('selL:$addr');
  }

  @override
  Future<bool> compareAddress() async => compareResult;

  @override
  Future<bool> compare(int h, int m, int l) async {
    // 简化：当 h==selH && m==selM && l==selL+1 返回 true，模拟 compareAddr 中的逻辑
    calls.add('compare:$h,$m,$l');
    return (h == selH && m == selM && l == selL + 1) || compareResult;
  }

  // 拦截 send/query，避免真实连接层
  @override
  Future<void> send(int a, int c, {int? t, int? d, int? g}) async {
    sentFrames.add([a, c, t ?? 1]);
    calls.add('send:$a,$c');
  }

  @override
  Future<int> query(int a, int c, {int? d, int? g}) async {
    calls.add('query:$a,$c');
    return nextQueryValue;
  }

  @override
  Future<void> setBright(int a, int b, {int? t, int? d, int? g}) async {
    calls.add('setBright:$a,$b');
  }
}

// 无需 StubManager，直接使用单例，并且本测试不会触发底层 connection。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'sendDelays': 0,
      'queryDelays': 0,
      'extDelays': 0,
      'invalidFrameTolerance': 0,
      'dimmingCurve': 'linear',
    });
  });

  group('DaliAddr basic', () {
    test('selectDevice emits', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      final events = <int>[];
      final sub = addr.selectedDeviceStream.listen(events.add);

      addr.selectDevice(10);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(base.selectedAddress, 10);
      expect(events, [10]);
      await sub.cancel();
    });
  });

  group('write/remove address', () {
    test('writeAddr and removeAddr/removeAllAddr', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);

      await addr.writeAddr(5, 12);
      expect(base.calls, containsAllInOrder(['setDTR:${12 * 2 + 1}', 'storeDTRAsAddr:5']));

      base.calls.clear();
      await addr.removeAddr(7);
      expect(base.calls, containsAllInOrder(['setDTR:255', 'storeDTRAsAddr:7']));

      base.calls.clear();
      await addr.removeAllAddr();
      // removeAllAddr 调用 removeAddr(broadcast=127)
      expect(base.calls, containsAllInOrder(['setDTR:255', 'storeDTRAsAddr:127']));
    });
  });

  group('search flows', () {
    test('searchAddr and stopSearch', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      base.online[1] = true;
      base.online[3] = true;

      final found = <List<int>>[];
      final states = <bool>[];
      final sub1 = addr.onlineDevicesStream.listen(found.add);
      final sub2 = addr.searchStateStream.listen(states.add);

      // 限制搜索数量以加速
      await addr.searchAddr(addr: 5);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(found.last, [1, 3]);
      expect(states.first, true);
      expect(states.last, false);

      // stopSearch 刷新状态和列表
      addr.stopSearch();
      expect(addr.isSearching, false);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('searchAddrRange', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      base.online.addAll({2: true, 4: true, 6: false});

      final found = <List<int>>[];
      final sub = addr.onlineDevicesStream.listen(found.add);

      await addr.searchAddrRange(start: 2, end: 5);
      expect(found.last, [2, 4]);
      await sub.cancel();
    });
  });

  group('compare helpers', () {
    test('compareSingleAddress with H/M/L', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);

      base.compareResult = true; // 让 compareAddress 返回 true
      expect(await addr.compareSingleAddress(1, 0x12), true);
      expect(base.selH, 0x12);
      expect(await addr.compareSingleAddress(2, 0x34), true);
      expect(base.selM, 0x34);
      expect(await addr.compareSingleAddress(3, 0x56), true);
      expect(base.selL, 0x56);
    });

    test('precompareNew returns narrowed range', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      base.compareResult = true; // 固定 true，快速收敛
      final r = await addr.precompareNew(1);
      expect(r.length, 2);
      expect(r[0] <= r[1], true);
    });
  });

  group('scene helpers', () {
    test('removeFromScene/getSceneBright call-through', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);

      // 由于我们没有完整的连接层，这里仅验证方法能调用而不抛出
      await addr.removeFromScene(3, 2);
      base.nextQueryValue = 77;
      final v = await addr.getSceneBright(3, 2);
      expect(v, 77);
    });
  });

  group('allocation light path', () {
    test('compareAddr simple happy path', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      addr.isAllocAddr = true;
      // 设定比较寄存器
      await base.queryAddressH(0x11);
      await base.queryAddressM(0x22);
      await base.queryAddressL(0x33);
      base.compareResult = true; // 让 compareAddress() 为真
      base.online.clear();
      base.online[0] = false; // 第一个空位
      base.queryShortAddrValue = 0; // 编程后查询返回匹配

      final res = await addr.compareAddr(0, 0, 0, 0);
      expect(res.length, 4);
      expect(res[3] is int, true);
      expect(res[3] >= 0 && res[3] <= 63, true);
    });

    test('compareMulti increments and stops', () async {
      final base = TestDaliBase();
      final addr = DaliAddr(base);
      addr.isAllocAddr = true;
      // 配置选中的寄存器以满足 compare 为真
      await base.queryAddressH(0x11);
      await base.queryAddressM(0x22);
      await base.queryAddressL(0x33);
      base.compareResult = true;
      base.online.clear();
      base.online[1] = false;
      base.queryShortAddrValue = 1;

      final next = await addr.compareMulti(0x11, 0x22, 0x33, 0);
      expect(next >= 0, true);
    });
  });
}
