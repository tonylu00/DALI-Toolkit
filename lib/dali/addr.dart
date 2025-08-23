import 'dart:async';

import 'package:flutter/material.dart';
import '../pages/device_selection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'base.dart';
import 'log.dart';
import 'errors.dart';

class DaliAddr {
  final DaliBase base;
  final StreamController<List<int>> _onlineDevicesController =
      StreamController<List<int>>.broadcast();
  final StreamController<int> _selectedDeviceController = StreamController<int>.broadcast();
  // 新增: 搜索状态流，便于外部监听搜索开始/结束，从而在无结果时刷新按钮状态
  final StreamController<bool> _searchStateController = StreamController<bool>.broadcast();
  List<int> onlineDevices = [];
  bool isSearching = false;
  // 扫描范围记忆（应用生命周期内）
  int scanRangeStart = 0;
  int scanRangeEnd = 63;

  /// 便于直接操作 isAllocAddr, lastAllocAddr 等字段
  bool get isAllocAddr => base.isAllocAddr;
  set isAllocAddr(bool v) => base.isAllocAddr = v;
  int get lastAllocAddr => base.lastAllocAddr;
  set lastAllocAddr(int v) => base.lastAllocAddr = v;

  DaliAddr(this.base);

  Stream<List<int>> get onlineDevicesStream => _onlineDevicesController.stream;
  Stream<int> get selectedDeviceStream => _selectedDeviceController.stream;
  Stream<bool> get searchStateStream => _searchStateController.stream;

  void selectDevice(int address) {
    base.selectedAddress = address;
    _selectedDeviceController.add(address);
  }

  // 统一日志 & 可选中断辅助
  void _logDaliError(DaliQueryException e, String ctx) {
    try {
      DaliLog.instance.errorLog('[$ctx]: ${e.toString()}');
    } catch (_) {
      DaliLog.instance.debugLog('ERROR [$ctx]: ${e.toString()}');
    }
  }

  bool _isFatalScanError(DaliQueryException e) =>
      e is DaliBusUnavailableException || e is DaliGatewayTimeoutException;

  /// Write device short address
  Future<void> writeAddr(int addr, int newAddr) async {
    final nAddr = newAddr * 2 + 1;
    try {
      await base.setDTR(nAddr);
      await base.storeDTRAsAddr(addr);
    } on DaliQueryException catch (e) {
      _logDaliError(e, 'writeAddr($addr->$newAddr)');
      rethrow; // 让上层决定是否提示用户
    }
    // await base.getOnlineStatus(addr);
  }

  /// Remove short address
  Future<void> removeAddr(int addr) async {
    try {
      await base.setDTR(0xff);
      await base.storeDTRAsAddr(addr);
    } on DaliQueryException catch (e) {
      _logDaliError(e, 'removeAddr($addr)');
      rethrow;
    }
    // await base.getOnlineStatus(addr);
  }

  /// Remove all short addresses
  Future<void> removeAllAddr() async {
    // await base.setBright(base.broadcast, 0);
    await removeAddr(base.broadcast);
  }

  Future<void> searchAddr({int addr = 63}) async {
    isSearching = true; // Set the flag to true when starting the search
    _searchStateController.add(true);
    onlineDevices.clear();
    for (int i = 0; i < addr; i++) {
      if (!isSearching) break; // Check the flag to stop the search
      try {
        final status = await base.getOnlineStatus(i);
        if (status) {
          DaliLog.instance.debugLog('INFO [searchAddr]: device $i is online');
          onlineDevices.add(i);
          _onlineDevicesController.add(List<int>.from(onlineDevices));
        }
      } on DaliDeviceNoResponseException {
        // 单个地址无响应: 忽略继续
        continue;
      } on DaliQueryException catch (e) {
        _logDaliError(e, 'searchAddr index=$i');
        if (_isFatalScanError(e)) {
          // 网关/总线级错误, 中止扫描
          break;
        } else {
          // 其他查询异常, 继续尝试后续地址
          continue;
        }
      }
    }
    DaliLog.instance.debugLog('INFO [searchAddr]: done. online devices: $onlineDevices');
    isSearching = false; // Reset the flag when the search is done
    _searchStateController.add(false);
    // 确保即便无设备也触发一次构建, 让弹窗由"正在扫描"切换到"暂无设备"
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  /// 新增: 按自定义起止地址扫描 (inclusive)
  Future<void> searchAddrRange({int start = 0, int end = 63}) async {
    if (start < 0) start = 0;
    if (end > 63) end = 63; // 物理限制
    if (start > end) {
      DaliLog.instance.debugLog('WARN [searchAddrRange]: invalid range start>$end');
      return;
    }
    isSearching = true;
    _searchStateController.add(true);
    onlineDevices.clear();
    for (int i = start; i <= end; i++) {
      if (!isSearching) break;
      try {
        final status = await base.getOnlineStatus(i);
        if (status) {
          onlineDevices.add(i);
          _onlineDevicesController.add(List<int>.from(onlineDevices));
        }
      } on DaliDeviceNoResponseException {
        continue; // 忽略
      } on DaliQueryException catch (e) {
        _logDaliError(e, 'searchAddrRange index=$i');
        if (_isFatalScanError(e)) {
          break; // 中断范围扫描
        } else {
          continue;
        }
      }
    }
    DaliLog.instance
        .debugLog('INFO [searchAddrRange]: done range [$start,$end] devices: $onlineDevices');
    isSearching = false;
    _searchStateController.add(false);
    // 同样在结束时再推送一次, 解决空结果不刷新的问题
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  void stopSearch() {
    isSearching = false;
    _searchStateController.add(false);
    // 停止后也推送一次当前结果, 避免 UI 停留在扫描状态
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  /// Compare a selected address
  Future<bool> compareSingleAddress(int typ, int addr) async {
    try {
      if (typ == 1) {
        await base.queryAddressH(addr);
      } else if (typ == 2) {
        await base.queryAddressM(addr);
      } else if (typ == 3) {
        await base.queryAddressL(addr);
      } else {
        DaliLog.instance.debugLog('ERROR [compareSingleAddress]: invalid typ=$typ');
      }
      int ret = await base.queryCmd(0xa9, 0x00);
      if (ret >= 0) return true;
      DaliLog.instance.debugLog('ERROR [compareSingleAddress]: unexpected ret=$ret');
      return false;
    } on DaliDeviceNoResponseException {
      return false; // 设备无响应 => 不匹配
    } on DaliGatewayTimeoutException catch (e) {
      _logDaliError(e, 'compareSingleAddress timeout typ=$typ addr=$addr');
      return false;
    } on DaliQueryException catch (e) {
      _logDaliError(e, 'compareSingleAddress typ=$typ addr=$addr');
      return false;
    }
  }

  /// Narrow down the range of search address
  Future<List<int>> precompareNew(int typ, [int? m]) async {
    int min = m ?? 0;
    int max = 255;
    while ((max - min) > 6) {
      double mi = (max - min) / 2 + min;
      int mid = mi.floor();
      bool ok = await compareSingleAddress(typ, mid);
      if (ok) {
        max = mid;
      } else {
        min = mid;
      }
    }
    return [min, max];
  }

  /// Compare specified type of address
  Future<int> compareAddress(int typ) async {
    int min = 0;
    int max = 255;
    int vAct = 0;
    List<int> mm = await precompareNew(typ);
    min = mm[0];
    max = mm[1];
    math.Random rnd = math.Random(528643246);

    for (int i = 0; i <= 100; i++) {
      if (!isAllocAddr) break;
      if (min >= max) break;
      int v = min + rnd.nextInt(max - min + 1);
      bool res = await compareSingleAddress(typ, v);
      if (res) {
        if (v == 0) {
          vAct = v;
          await compareSingleAddress(typ, v);
          break;
        }
        bool res2 = await compareSingleAddress(typ, v - 1);
        if (res2) {
          max = v - 1;
        } else {
          vAct = v - 1;
          await compareSingleAddress(typ, v - 1);
          break;
        }
      } else if (v <= 254) {
        bool res3 = await compareSingleAddress(typ, v + 1);
        if (res3) {
          vAct = v;
          await compareSingleAddress(typ, v);
          break;
        } else {
          min = v + 1;
        }
      } else {
        DaliLog.instance.debugLog('ERROR [compareAddress]: failed to compare address');
        break;
      }
    }
    return vAct;
  }

  /// Another approach to compare address
  Future<int> compareAddressNew(int typ, [int? m]) async {
    int minVal = m ?? 0;
    int maxVal = 255;
    int vAct = 0;
    List<int> mm = await precompareNew(typ, minVal);
    minVal = mm[0];
    maxVal = mm[1];
    int v = maxVal;
    for (int i = 0; i <= 10; i++) {
      bool ok = await compareSingleAddress(typ, v);
      if (ok) {
        if (v == 0) {
          vAct = v;
          await compareSingleAddress(typ, v);
          break;
        }
        bool ok2 = await compareSingleAddress(typ, v - 1);
        if (ok2) {
          maxVal = v - 1;
        } else {
          vAct = v - 1;
          await compareSingleAddress(typ, v - 1);
          break;
        }
      }
    }
    return vAct;
  }

  /// Compare address and allocating from short addr 'ad'
  Future<List<dynamic>> compareAddr(int ad, int? minH, int? minM, int? minL) async {
    int? retH, retM, retL;
    if (ad > 63) {
      return [retH, retM, retL, 63];
    }
    await base.compare(128, 0, 0);
    // Note: In original code, compareAddress signature had optional min params.
    // Here we just call compareAddress(1), etc. If needed, pass minH in.
    retH = await compareAddress(1);
    retM = await compareAddress(2);
    retL = await compareAddress(3);
    if (!isAllocAddr) return [0, 0, 0, ad];
    if (retH == 0 && retM == 0 && retL == 0) {
      return [retH, retM, retL, ad];
    }

    bool res = await base.compare(retH, retM, retL + 1);
    if (res) {
      while (await base.getOnlineStatus(ad)) {
        ad++;
      }
      await base.programShortAddr(ad);
      int qsa = await base.queryShortAddr();
      if (qsa == ad) {
        await base.withdraw();
        await base.setBright(ad, 254);
      } else {
        DaliLog.instance.debugLog('ERROR [compareAddr]: program short addr failed');
      }
    } else {
      DaliLog.instance.debugLog('ERROR [compareAddr]: search device failed');
      isAllocAddr = false;
      return [0, 0, 0, ad];
    }
    return [retH, retM, retL, ad];
  }

  /// Relays address compare speedup by LSB + 1
  Future<int> compareMulti(int h, int m, int l, int ad) async {
    int addr = ad + 1;
    int retL = l;
    for (int i = 0; i < 12; i++) {
      if (!isAllocAddr) return addr - 1;
      retL++;
      if (retL > 255) break;
      bool ok = await base.compare(h, m, retL);
      if (ok) {
        while (await base.getOnlineStatus(addr)) {
          addr++;
        }
        await base.programShortAddr(addr);
        int qsa = await base.queryShortAddr();
        if (qsa == addr) {
          await base.withdraw();
          await base.setBright(addr, 254);
          // place for memory writes, not implemented
          addr++;
        } else {
          DaliLog.instance.debugLog('ERROR [compareMulti]: E [DALI]: program addr err');
        }
      } else {
        addr--;
        break;
      }
    }
    return addr;
  }

  /// Compare and allocate short address to all new device
  Future<void> allocateAllAddr([int? ads]) async {
    final log = DaliLog.instance;
    int ad = ads ?? 0;
    isAllocAddr = true;
    lastAllocAddr = 255;
    int fatalErrorCount = 0; // 连续致命错误计数
    const int fatalErrorLimit = 5; // 达到后终止
    for (int i = 0; i <= 80; i++) {
      if (!isAllocAddr) break;
      bool anyDevice;
      try {
        bool dev1 = await base.compare(255, 255, 255);
        if (dev1) {
          anyDevice = true;
          await Future.delayed(const Duration(milliseconds: 100));
        } else if (await base.compare(255, 255, 255)) {
          anyDevice = true;
          await Future.delayed(const Duration(milliseconds: 100));
        } else if (await base.compare(255, 255, 255)) {
          anyDevice = true;
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          anyDevice = false;
        }
      } on DaliDeviceNoResponseException {
        // 视为当前无新设备, 不增加 fatal 计数
        anyDevice = false;
      } on DaliGatewayTimeoutException catch (e) {
        _logDaliError(e, 'allocateAllAddr gateway timeout pre-compare');
        anyDevice = false; // 可能暂时性, 继续但允许退出
        fatalErrorCount++;
      } on DaliBusUnavailableException catch (e) {
        _logDaliError(e, 'allocateAllAddr bus unavailable pre-compare');
        fatalErrorCount++;
        anyDevice = false;
      } on DaliQueryException catch (e) {
        _logDaliError(e, 'allocateAllAddr pre-compare unexpected');
        anyDevice = false; // 非致命
      }
      if (!anyDevice) {
        if (fatalErrorCount >= fatalErrorLimit) {
          log.errorLog('abort due to repeated fatal errors ($fatalErrorCount)');
          break;
        }
        log.infoLog('no devices to compare (fatalErrors=$fatalErrorCount)');
        break;
      }

      log.infoLog('start comparing address $ad');
      List<dynamic> retVals;
      try {
        retVals = await compareAddr(ad, 0, 0, 0);
      } on DaliQueryException catch (e) {
        _logDaliError(e, 'allocateAllAddr compareAddr');
        fatalErrorCount++;
        if (fatalErrorCount >= fatalErrorLimit) {
          log.errorLog('abort compareAddr due to repeated fatal errors');
          break;
        }
        continue; // 跳过当前循环
      }
      ad = retVals[3];
      if (!isAllocAddr) break;
      if (retVals[0] == 0 && retVals[1] == 0 && retVals[2] == 0) {
        // skip
      } else {
        i = 0;
      }
      // place for mem.inter.WriteBit(18, ad, 1);
      try {
        ad = await compareMulti(retVals[0], retVals[1], retVals[2] + 1, ad);
      } on DaliQueryException catch (e) {
        _logDaliError(e, 'allocateAllAddr compareMulti');
        fatalErrorCount++;
        if (fatalErrorCount >= fatalErrorLimit) {
          log.errorLog('abort compareMulti due to repeated fatal errors');
          break;
        }
      }
      // place for mem.inter.Write(660, ad+1);
      lastAllocAddr = ad;
      ad++;
      if (ad > 63) {
        log.errorLog('compare process failed, address out of range');
        isAllocAddr = false;
        break;
      }
      if (i == 80) {
        log.infoLog('compare process failed, retry limit reached');
        isAllocAddr = false;
        break;
      }
    }
    if (!isAllocAddr) return;
    isAllocAddr = false;
    if (ad <= 0) {
      lastAllocAddr = 255;
      // placeholder for sys.publish
    } else {
      log.infoLog('allocate all address done, last addr: ${ad - 1}');
      lastAllocAddr = ad - 1;
      // placeholder for sys.publish
    }
  }

  Future<void> stopAllocAddr() async {
    isAllocAddr = false;
  }

  /// Remove device from scene
  Future<void> removeFromScene(int addr, int scene) async {
    int value = scene + 80;
    await base.send(addr, value, t: 2);
  }

  /// Get scene brightness
  Future<int> getSceneBright(int addr, int scene) async {
    int value = scene + 176;
    return await base.query(addr, value);
  }

  /// Remove all short address, then allocate new
  Future<void> resetAndAllocAddr([int n = 0]) async {
    final prefs = await SharedPreferences.getInstance();
    final log = DaliLog.instance;
    final isRemoveAddr = prefs.getBool('removeAddr') ?? false;
    final isCloseLight = prefs.getBool('closeLight') ?? false;
    int startTime = base.mcuTicks();
    isAllocAddr = true;
    // placeholder for mem.inter.WriteBit(7, 0, 1);
    // await base.reset(base.broadcast);
    await Future.delayed(const Duration(milliseconds: 100));
    if (isCloseLight) {
      await base.off(base.broadcast);
      log.infoLog('close all lights done');
      await Future.delayed(const Duration(milliseconds: 100));
    }
    try {
      await base.terminate();
      await Future.delayed(const Duration(milliseconds: 200));
      if (isRemoveAddr) {
        await base.initialiseAll();
        await Future.delayed(const Duration(milliseconds: 200));
        await removeAllAddr();
        log.infoLog('remove all short address');
      } else {
        await base.initialise();
        log.infoLog('initialise unaddressed');
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await base.randomise();
      await Future.delayed(const Duration(milliseconds: 100));
      await base.randomise();
      await Future.delayed(const Duration(milliseconds: 300));
      await allocateAllAddr(n);
    } on DaliQueryException catch (e) {
      _logDaliError(e, 'resetAndAllocAddr');
      isAllocAddr = false; // 确保状态恢复
    }
    int elapsed = base.mcuTicks() - startTime;
    log.infoLog('reset and allocate address done in $elapsed ms');
    // placeholder for mem.inter.WriteBit(7, 3, 0);
  }

  void openDeviceSelectionPage(BuildContext context) {
    // 直接跳转到页面版本
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceSelectionPage(daliAddr: this),
      ),
    );
  }

  // _buildDevicesList 已内联至对话框逻辑，移除旧方法

  void dispose() {
    _onlineDevicesController.close();
    _selectedDeviceController.close();
    _searchStateController.close();
  }
}
