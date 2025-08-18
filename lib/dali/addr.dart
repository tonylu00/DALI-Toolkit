import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../toast.dart';
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
          bool broadcastMode = base.selectedAddress == base.broadcast;
          return StatefulBuilder(
            builder: (ctx, setState) {
              Widget scanButton = ElevatedButton.icon(
                onPressed: () {
                  if (isSearching) {
                    stopSearch();
                  } else {
                    if (scanRangeStart > scanRangeEnd) {
                      final t = scanRangeStart;
                      scanRangeStart = scanRangeEnd;
                      scanRangeEnd = t;
                    }
                    searchAddrRange(start: scanRangeStart, end: scanRangeEnd);
                  }
                  setState(() {}); // 更新按钮状态
                },
                icon: Icon(isSearching ? Icons.stop : Icons.search),
                label: Text(
                    isSearching ? 'device_search.stop_scan'.tr() : 'device_search.start_scan'.tr()),
                style: isSearching
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      )
                    : null,
              );
              return AlertDialog(
                title: Row(
                  children: [
                    Expanded(child: const Text('Online Devices').tr()),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: broadcastMode,
                          onChanged: (v) {
                            // 勾选进入广播模式；取消勾选需要有设备可选
                            if (v == true) {
                              stopSearch();
                              base.selectedAddress = base.broadcast;
                              _selectedDeviceController.add(base.selectedAddress);
                              broadcastMode = true;
                              setState(() {});
                              return;
                            }
                            // 取消广播模式
                            final devices = onlineDevices;
                            if (devices.isEmpty) {
                              // 没有设备，不能取消，保持广播
                              // 使用自定义 Toast 替换 SnackBar 提示
                              ToastManager()
                                  .showInfoToast('device_search.cannot_exit_broadcast_no_devices');
                              setState(() {});
                              return;
                            }
                            // 如果用户之前没有选过单个设备，则默认选中第一个
                            if (base.selectedAddress == base.broadcast) {
                              base.selectedAddress = devices.first;
                              _selectedDeviceController.add(base.selectedAddress);
                            }
                            broadcastMode = false;
                            setState(() {});
                          },
                        ),
                        Text('device_search.broadcast'.tr()),
                      ],
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: scanRangeStart.toString(),
                              decoration:
                                  InputDecoration(labelText: 'device_search.range_start'.tr()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = int.tryParse(v) ?? scanRangeStart;
                                if (n >= 0 && n <= 63) scanRangeStart = n;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: scanRangeEnd.toString(),
                              decoration:
                                  InputDecoration(labelText: 'device_search.range_end'.tr()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = int.tryParse(v) ?? scanRangeEnd;
                                if (n >= 0 && n <= 63) scanRangeEnd = n;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          scanButton,
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: StreamBuilder<List<int>>(
                          stream: onlineDevicesStream,
                          builder: (context, snapshot) {
                            final devices = snapshot.data ?? onlineDevices;
                            if (isSearching && devices.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                        width: 36, height: 36, child: CircularProgressIndicator()),
                                    const SizedBox(height: 12),
                                    Text('short_addr_manager.scanning').tr(),
                                  ],
                                ),
                              );
                            }
                            if (!isSearching && devices.isEmpty) {
                              return Center(child: Text('short_addr_manager.empty').tr());
                            }
                            return ListView.builder(
                              itemCount: devices.length,
                              itemBuilder: (c, i) {
                                final a = devices[i];
                                final selected = !broadcastMode && a == base.selectedAddress;
                                return ListTile(
                                  selected: selected,
                                  selectedColor: Theme.of(context).colorScheme.primary,
                                  selectedTileColor:
                                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  title: Text('Device $a'),
                                  onTap: () {
                                    if (broadcastMode) {
                                      // 禁止在广播模式选择设备
                                      // 使用 ScaffoldMessenger 显示简易提示；若有 ToastManager 可替换
                                      ToastManager()
                                          .showInfoToast('device_search.broadcast_selected_toast');
                                      return;
                                    }
                                    base.selectedAddress = a;
                                    _selectedDeviceController.add(a);
                                    setState(() {});
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      stopSearch();
                      Navigator.of(context).pop();
                    },
                    child: Text('Close').tr(),
                  )
                ],
              );
            },
          );
        });
  }

  // _buildDevicesList 已内联至对话框逻辑，移除旧方法

  void dispose() {
    _onlineDevicesController.close();
    _selectedDeviceController.close();
  }
}
