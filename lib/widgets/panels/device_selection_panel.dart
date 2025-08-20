import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../toast.dart';
import '../../dali/addr.dart';
import '../../connection/manager.dart';

/// 可复用设备选择面板，可嵌入页面 / 抽屉 / 横屏布局。
class DeviceSelectionPanel extends StatefulWidget {
  final DaliAddr daliAddr;
  final bool showTitle; // 控制是否在面板内部显示标题（页面中可由 AppBar 处理）
  const DeviceSelectionPanel({super.key, required this.daliAddr, this.showTitle = false});

  @override
  State<DeviceSelectionPanel> createState() => _DeviceSelectionPanelState();
}

class _DeviceSelectionPanelState extends State<DeviceSelectionPanel> {
  DaliAddr get addr => widget.daliAddr;
  late int rangeStart;
  late int rangeEnd;
  late bool broadcastMode;
  late TextEditingController _addrInputCtrl; // 手动输入地址 (0-63)
  bool _groupAddr = false; // 是否组地址 (addr + 64)
  DateTime? _lastToastTime;

  @override
  void initState() {
    super.initState();
    rangeStart = addr.scanRangeStart;
    rangeEnd = addr.scanRangeEnd;
    broadcastMode = addr.base.selectedAddress == addr.base.broadcast;
    final sel = addr.base.selectedAddress;
    if (sel >= 64 && sel < 127) {
      _groupAddr = true;
      _addrInputCtrl = TextEditingController(text: (sel - 64).toString());
    } else {
      _groupAddr = false;
      _addrInputCtrl =
          TextEditingController(text: sel == addr.base.broadcast ? '0' : sel.toString());
    }
    addr.searchStateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _addrInputCtrl.dispose();
    super.dispose();
  }

  void _toggleScan() {
    // 若是开始扫描，先做连接与总线前置检查（内部会 toast 提示）
    if (!addr.isSearching) {
      final ok = ConnectionManager.instance.ensureReadyForOperation();
      if (!ok) {
        return; // 失败直接返回，不进入 setState 切换按钮
      }
    }
    setState(() {
      if (addr.isSearching) {
        addr.stopSearch();
      } else {
        if (rangeStart > rangeEnd) {
          final t = rangeStart;
          rangeStart = rangeEnd;
          rangeEnd = t;
        }
        addr.scanRangeStart = rangeStart;
        addr.scanRangeEnd = rangeEnd;
        addr.searchAddrRange(start: rangeStart, end: rangeEnd);
      }
    });
  }

  void _toggleBroadcast(bool? v) {
    if (v == true) {
      addr.stopSearch();
      addr.base.selectedAddress = addr.base.broadcast;
      addr.selectDevice(addr.base.selectedAddress);
      setState(() {
        broadcastMode = true;
        // 广播模式下不使用组地址
        _groupAddr = false;
      });
      return;
    }
    // 退出广播：若有在线设备选第一个，否则选0
    final devices = List<int>.from(addr.onlineDevices)..sort();
    int newAddr = devices.isNotEmpty ? devices.first : 0;
    addr.base.selectedAddress = newAddr;
    addr.selectDevice(newAddr);
    setState(() {
      broadcastMode = false;
      _groupAddr = false;
      _addrInputCtrl.text = newAddr.toString();
    });
  }

  void _toggleGroupAddr(bool? v) {
    if (broadcastMode) return; // 广播下不可用
    final newVal = v ?? false;
    if (newVal != _groupAddr) {
      setState(() {
        _groupAddr = newVal;
        // 切换组地址时清空输入框，不立即改变已存地址 (等待用户再次输入)
        _addrInputCtrl.clear();
      });
    }
  }

  Widget _buildControls(bool wide) {
    final scanBtn = ElevatedButton.icon(
      onPressed: _toggleScan,
      icon: Icon(addr.isSearching ? Icons.stop : Icons.search),
      label:
          Text(addr.isSearching ? 'device_search.stop_scan'.tr() : 'device_search.start_scan'.tr()),
      style: addr.isSearching
          ? ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white)
          : null,
    );
    final rangeInputs = Row(children: [
      Expanded(
          child: TextFormField(
        initialValue: rangeStart.toString(),
        decoration: InputDecoration(labelText: 'device_search.range_start'.tr()),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v) ?? rangeStart;
          if (n >= 0 && n <= 63) rangeStart = n;
        },
      )),
      const SizedBox(width: 8),
      Expanded(
          child: TextFormField(
        initialValue: rangeEnd.toString(),
        decoration: InputDecoration(labelText: 'device_search.range_end'.tr()),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v) ?? rangeEnd;
          if (n >= 0 && n <= 63) rangeEnd = n;
        },
      )),
      const SizedBox(width: 8),
      scanBtn,
    ]);
    final titleRow = widget.showTitle
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text('Online Devices', style: Theme.of(context).textTheme.titleMedium).tr(),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _addrInputCtrl,
                      enabled: !broadcastMode,
                      decoration: const InputDecoration(
                        labelText: 'Addr',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: _onAddrChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(children: [
                    Checkbox(value: _groupAddr, onChanged: broadcastMode ? null : _toggleGroupAddr),
                    Text('device_search.group_addr'.tr()),
                  ]),
                  const SizedBox(width: 8),
                  Checkbox(value: broadcastMode, onChanged: _toggleBroadcast),
                  Text('device_search.broadcast'.tr()),
                ])
              ],
            ),
          )
        : Row(
            children: [
              const Spacer(),
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _addrInputCtrl,
                    enabled: !broadcastMode,
                    decoration: const InputDecoration(labelText: 'Addr', isDense: true),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _onAddrChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Row(children: [
                  Checkbox(value: _groupAddr, onChanged: broadcastMode ? null : _toggleGroupAddr),
                  Text('device_search.group_addr'.tr()),
                ]),
                const SizedBox(width: 8),
                Checkbox(value: broadcastMode, onChanged: _toggleBroadcast),
                Text('device_search.broadcast'.tr()),
              ])
            ],
          );
    final column = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      titleRow,
      const SizedBox(height: 4),
      rangeInputs,
    ]);
    return column;
  }

  void _onAddrChanged(String value) {
    if (broadcastMode) return; // 广播模式不处理
    final text = value.trim();
    if (text.isEmpty) {
      _throttleToast('address.input.empty');
      return;
    }
    final v = int.tryParse(text);
    if (v == null) {
      _throttleToast('address.input.empty');
      return;
    }
    final max = _groupAddr ? 15 : 63;
    if (v < 0 || v > max) {
      _throttleToast(_groupAddr ? 'address.input.invalid_group' : 'address.input.invalid_single');
      return;
    }
    // 合法，更新
    final actual = _groupAddr ? v + 64 : v;
    addr.base.selectedAddress = actual;
    addr.selectDevice(actual);
    setState(() {});
  }

  void _throttleToast(String key) {
    final now = DateTime.now();
    if (_lastToastTime != null &&
        now.difference(_lastToastTime!) < const Duration(milliseconds: 800)) {
      return; // 节流
    }
    _lastToastTime = now;
    ToastManager().showErrorToast(key.tr());
  }

  Widget _buildDeviceList() {
    return StreamBuilder<List<int>>(
      stream: addr.onlineDevicesStream,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? addr.onlineDevices;
        if (addr.isSearching && devices.isEmpty) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 36, height: 36, child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text('short_addr_manager.scanning').tr(),
          ]));
        }
        if (!addr.isSearching && devices.isEmpty) {
          return Center(child: Text('short_addr_manager.empty').tr());
        }
        return ListView.builder(
          itemCount: devices.length,
          itemBuilder: (c, i) {
            final a = devices[i];
            final selected = !broadcastMode && a == addr.base.selectedAddress;
            return ListTile(
              selected: selected,
              selectedColor: Theme.of(context).colorScheme.primary,
              selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              title: Text('Device $a'),
              onTap: () {
                if (broadcastMode) {
                  ToastManager().showInfoToast('device_search.broadcast_selected_toast');
                  return;
                }
                addr.base.selectedAddress = a;
                addr.selectDevice(a);
                if (!_groupAddr) {
                  _addrInputCtrl.text = a.toString();
                }
                setState(() {});
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 720;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 320,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16), child: _buildControls(true))),
          Expanded(child: Padding(padding: const EdgeInsets.all(8), child: _buildDeviceList())),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(16), children: [
        _buildControls(false),
        const SizedBox(height: 16),
        SizedBox(height: MediaQuery.of(context).size.height * 0.55, child: _buildDeviceList()),
      ]);
    });
  }
}
