import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'base.dart';
import 'log.dart';

class DaliAddr {
  final DaliBase base;
  final StreamController<List<int>> _onlineDevicesController =
      StreamController<List<int>>.broadcast();
  final StreamController<int> _selectedDeviceController = StreamController<int>.broadcast();
  List<int> onlineDevices = [];
  bool isSearching = false;

  /// 便于直接操作 isAllocAddr, lastAllocAddr 等字段
  bool get isAllocAddr => base.isAllocAddr;
  set isAllocAddr(bool v) => base.isAllocAddr = v;
  int get lastAllocAddr => base.lastAllocAddr;
  set lastAllocAddr(int v) => base.lastAllocAddr = v;

  DaliAddr(this.base);

  Stream<List<int>> get onlineDevicesStream => _onlineDevicesController.stream;
  Stream<int> get selectedDeviceStream => _selectedDeviceController.stream;

  void selectDevice(int address) {
    base.selectedAddress = address;
    _selectedDeviceController.add(address);
  }

  /// Write device short address
  Future<void> writeAddr(int addr, int newAddr) async {
    await base.setDTR(newAddr);
    await base.storeDTRAsAddr(addr);
    // await base.getOnlineStatus(addr);
  }

  /// Remove short address
  Future<void> removeAddr(int addr) async {
    await base.setDTR(0xff);
    await base.storeDTRAsAddr(addr);
    // await base.getOnlineStatus(addr);
  }

  /// Remove all short addresses
  Future<void> removeAllAddr() async {
    // await base.setBright(base.broadcast, 0);
    await removeAddr(base.broadcast);
  }

  Future<void> searchAddr({int addr = 63}) async {
    isSearching = true; // Set the flag to true when starting the search
    onlineDevices.clear();
    for (int i = 0; i < addr; i++) {
      if (!isSearching) break; // Check the flag to stop the search
      final status = await base.getOnlineStatus(i);
      if (status) {
        debugPrint('INFO [searchAddr]: device $i is online');
        onlineDevices.add(i);
        _onlineDevicesController.add(onlineDevices);
      }
    }
    debugPrint('INFO [searchAddr]: done. online devices: $onlineDevices');
    isSearching = false; // Reset the flag when the search is done
    // 确保即便无设备也触发一次构建, 让弹窗由"正在扫描"切换到"暂无设备"
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  /// 新增: 按自定义起止地址扫描 (inclusive)
  Future<void> searchAddrRange({int start = 0, int end = 63}) async {
    if (start < 0) start = 0;
    if (end > 63) end = 63; // 物理限制
    if (start > end) {
      debugPrint('WARN [searchAddrRange]: invalid range start>$end');
      return;
    }
    isSearching = true;
    onlineDevices.clear();
    for (int i = start; i <= end; i++) {
      if (!isSearching) break;
      final status = await base.getOnlineStatus(i);
      if (status) {
        onlineDevices.add(i);
        _onlineDevicesController.add(List<int>.from(onlineDevices));
      }
    }
    debugPrint('INFO [searchAddrRange]: done range [$start,$end] devices: $onlineDevices');
    isSearching = false;
    // 同样在结束时再推送一次, 解决空结果不刷新的问题
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  void stopSearch() {
    isSearching = false;
    // 停止后也推送一次当前结果, 避免 UI 停留在扫描状态
    _onlineDevicesController.add(List<int>.from(onlineDevices));
  }

  /// Compare a selected address
  Future<bool> compareSingleAddress(int typ, int addr) async {
    if (typ == 1) {
      await base.queryAddressH(addr);
    } else if (typ == 2) {
      await base.queryAddressM(addr);
    } else if (typ == 3) {
      await base.queryAddressL(addr);
    } else {
      debugPrint('ERROR [compareSingleAddress]: failed to compare single address');
    }
    int ret = await base.queryCmd(0xa9, 0x00);
    if (ret == -1) {
      return false;
    } else if (ret >= 0) {
      return true;
    } else {
      debugPrint('ERROR [compareSingleAddress]: failed to compare address, return $ret');
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
        debugPrint('ERROR [compareAddress]: failed to compare address');
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
        debugPrint('ERROR [compareAddr]: program short addr failed');
      }
    } else {
      debugPrint('ERROR [compareAddr]: search device failed');
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
          debugPrint('ERROR [compareMulti]: E [DALI]: program addr err');
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
    for (int i = 0; i <= 80; i++) {
      if (!isAllocAddr) break;
      bool dev1 = await base.compare(255, 255, 255);
      if (dev1) {
        await Future.delayed(const Duration(milliseconds: 100));
      } else if (await base.compare(255, 255, 255)) {
        await Future.delayed(const Duration(milliseconds: 100));
      } else if (await base.compare(255, 255, 255)) {
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        log.addLog('INFO [allocateAllAddr]: no devices to compare');
        break;
      }
      log.addLog('INFO [allocateAllAddr]: start comparing address $ad');
      List<dynamic> retVals = await compareAddr(ad, 0, 0, 0);
      ad = retVals[3];
      if (!isAllocAddr) break;
      if (retVals[0] == 0 && retVals[1] == 0 && retVals[2] == 0) {
        // skip
      } else {
        i = 0;
      }
      // place for mem.inter.WriteBit(18, ad, 1);
      ad = await compareMulti(retVals[0], retVals[1], retVals[2] + 1, ad);
      // place for mem.inter.Write(660, ad+1);
      lastAllocAddr = ad;
      ad++;
      if (ad > 63) {
        log.addLog('ERROR [allocateAllAddr]: compare process failed, address out of range');
        isAllocAddr = false;
        break;
      }
      if (i == 80) {
        log.addLog('INFO [allocateAllAddr]: compare process failed, retry limit reached');
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
      log.addLog('INFO [allocateAllAddr]: allocate all address done, last addr: ${ad - 1}');
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
      log.addLog('INFO [resetAndAllocAddr]: close all lights done');
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await base.terminate();
    await Future.delayed(const Duration(milliseconds: 200));
    if (isRemoveAddr) {
      await base.initialiseAll();
      await Future.delayed(const Duration(milliseconds: 200));
      await removeAllAddr();
      log.addLog('INFO [resetAndAllocAddr]: remove all short address');
    } else {
      await base.initialise();
      log.addLog('INFO [resetAndAllocAddr]: initialise unaddressed');
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await base.randomise();
    await Future.delayed(const Duration(milliseconds: 100));
    await base.randomise();
    await Future.delayed(const Duration(milliseconds: 300));
    await allocateAllAddr(n);
    int elapsed = base.mcuTicks() - startTime;
    log.addLog('INFO [resetAndAllocAddr]: reset and allocate address done in $elapsed ms');
    // placeholder for mem.inter.WriteBit(7, 3, 0);
  }

  void showDevicesDialog(BuildContext context) {
    final currentContext = context;
    showDialog(
      context: currentContext,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Online Devices').tr(),
          content: SizedBox(
            width: double.maxFinite,
            child: StreamBuilder<List<int>>(
              stream: onlineDevicesStream,
              builder: (context, snapshot) {
                // 根据 isSearching 与当前已发现设备数决定显示内容，避免在无结果时一直转圈
                final devices = snapshot.data ?? onlineDevices;
                if (isSearching) {
                  if (devices.isEmpty) {
                    // 扫描中但尚未发现设备
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 32, height: 32, child: CircularProgressIndicator()),
                          const SizedBox(height: 12),
                          Text('short_addr_manager.scanning').tr(),
                        ],
                      ),
                    );
                  }
                  // 扫描中且已有部分设备 => 显示列表并在顶部展示一个轻量进度指示
                  return Column(
                    children: [
                      LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _buildDevicesList(devices, context),
                      ),
                    ],
                  );
                }
                // 非扫描状态
                if (devices.isEmpty) {
                  // 扫描结束仍无设备
                  return Center(child: Text('short_addr_manager.empty').tr());
                }
                return _buildDevicesList(devices, context);
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                isSearching = false;
                Navigator.of(context).pop();
              },
              child: const Text('Close').tr(),
            ),
          ],
        );
      },
    );
  }

  /// 构建设备列表（提取方法以复用）
  Widget _buildDevicesList(List<int> devices, BuildContext dialogContext) {
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final addr = devices[index];
        return ListTile(
          title: Text('Device $addr'),
          onTap: () {
            base.selectedAddress = addr;
            _selectedDeviceController.add(addr);
            isSearching = false;
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  void dispose() {
    _onlineDevicesController.close();
    _selectedDeviceController.close();
  }
}
