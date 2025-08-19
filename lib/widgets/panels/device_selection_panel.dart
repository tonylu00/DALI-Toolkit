import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    rangeStart = addr.scanRangeStart;
    rangeEnd = addr.scanRangeEnd;
    broadcastMode = addr.base.selectedAddress == addr.base.broadcast;
    addr.searchStateStream.listen((_) {
      if (mounted) setState(() {});
    });
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
      });
      return;
    }
    final devices = addr.onlineDevices;
    if (devices.isEmpty) {
      ToastManager().showInfoToast('device_search.cannot_exit_broadcast_no_devices');
      setState(() {});
      return;
    }
    if (addr.base.selectedAddress == addr.base.broadcast) {
      addr.base.selectedAddress = devices.first;
      addr.selectDevice(addr.base.selectedAddress);
    }
    setState(() {
      broadcastMode = false;
    });
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
    final broadcastToggle = Row(mainAxisSize: MainAxisSize.min, children: [
      Checkbox(value: broadcastMode, onChanged: _toggleBroadcast),
      Text('device_search.broadcast'.tr()),
    ]);
    final column = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.showTitle)
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text('Online Devices', style: Theme.of(context).textTheme.titleMedium).tr(),
        ),
      broadcastToggle,
      const SizedBox(height: 12),
      rangeInputs,
    ]);
    return column;
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
