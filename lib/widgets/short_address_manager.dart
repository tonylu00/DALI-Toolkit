import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../connection/manager.dart';
import '../dali/addr.dart';
import '../dali/log.dart';
import '../toast.dart';
import 'reorder_handle.dart';

/// 短地址管理组件
/// 功能: 扫描在线设备、显示列表、选择设备、修改短地址、删除短地址、拖拽重新排序
/// 通过 onScanResult 输出扫描结果供外部使用
class ShortAddressManager extends StatefulWidget {
  final DaliAddr daliAddr;
  final void Function(List<int> addresses)? onScanResult;
  final double itemHeight;

  const ShortAddressManager(
      {super.key, required this.daliAddr, this.onScanResult, this.itemHeight = 56});

  @override
  State<ShortAddressManager> createState() => _ShortAddressManagerState();
}

class _ShortAddressManagerState extends State<ShortAddressManager> {
  late List<int> _addresses; // 当前在线设备地址
  bool _scanning = false;
  StreamSubscription<List<int>>? _sub;
  bool _selectionMode = false;
  final Set<int> _selected = {};
  // 范围与排序配置
  final TextEditingController _scanStartCtrl = TextEditingController(text: '0');
  final TextEditingController _scanEndCtrl = TextEditingController(text: '63');
  final TextEditingController _reorderStartCtrl = TextEditingController(text: '0');
  final TextEditingController _reorderEndCtrl = TextEditingController(text: '63');
  bool _applyingOrder = false;
  bool _cancelApply = false;

  @override
  void initState() {
    super.initState();
    _addresses = List<int>.from(widget.daliAddr.onlineDevices);
    _sub = widget.daliAddr.onlineDevicesStream.listen((list) {
      setState(() {
        _addresses = List<int>.from(list)..sort();
      });
      widget.onScanResult?.call(_addresses);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scanStartCtrl.dispose();
    _scanEndCtrl.dispose();
    _reorderStartCtrl.dispose();
    _reorderEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    // 连接检查
    final connection = ConnectionManager.instance.connection;
    if (!connection.isDeviceConnected()) {
      // 改为统一 toast 提示
      ToastManager().showErrorToast('Device not connected'.tr());
      return;
    }
    int? start = int.tryParse(_scanStartCtrl.text);
    int? end = int.tryParse(_scanEndCtrl.text);
    start ??= 0;
    end ??= 63;
    if (start < 0) start = 0;
    if (end > 63) end = 63;
    if (start > end) {
      _showSnack('short_addr_manager.invalid_scan_range'.tr());
      return;
    }
    setState(() => _scanning = true);
    try {
      await widget.daliAddr.searchAddrRange(start: start, end: end);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _stopScan() {
    widget.daliAddr.stopSearch();
    setState(() => _scanning = false);
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selected.clear();
    });
  }

  void _toggleSelect(int addr) {
    setState(() {
      if (_selected.contains(addr)) {
        _selected.remove(addr);
      } else {
        _selected.add(addr);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _addresses.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_addresses);
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('short_addr_manager.batch_delete_title').tr(),
        content:
            Text('short_addr_manager.batch_delete_confirm'.tr(args: [_selected.length.toString()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No').tr()),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes').tr()),
        ],
      ),
    );
    if (ok != true) return;
    try {
      for (final a in _selected.toList()) {
        await widget.daliAddr.removeAddr(a);
      }
      await _startScan();
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
      _showSnack('short_addr_manager.batch_delete_success'.tr());
    } catch (e) {
      _showSnack('short_addr_manager.batch_delete_fail'.tr(args: [e.toString()]));
    }
  }

  Future<void> _renameAddress(int oldAddr, int newAddr) async {
    if (!ConnectionManager.instance.ensureReadyForOperation()) return;
    if (newAddr < 0 || newAddr > 63) {
      _showSnack('short_addr_manager.invalid_range'.tr());
      return;
    }
    if (_addresses.contains(newAddr) && newAddr != oldAddr) {
      _showSnack('short_addr_manager.duplicate_addr'.tr());
      return;
    }
    try {
      await widget.daliAddr.writeAddr(oldAddr, newAddr);
      await widget.daliAddr.base.getOnlineStatus(newAddr); // 刷新状态
      await _startScan();
      _showSnack('short_addr_manager.modify_success'.tr());
    } catch (e) {
      _showSnack('short_addr_manager.modify_fail'.tr(args: [e.toString()]));
    }
  }

  Future<void> _deleteAddress(int addr) async {
    if (!ConnectionManager.instance.ensureReadyForOperation()) return;
    try {
      await widget.daliAddr.removeAddr(addr);
      await _startScan();
      _showSnack('short_addr_manager.delete_success'.tr());
    } catch (e) {
      _showSnack('short_addr_manager.delete_fail'.tr(args: [e.toString()]));
    }
  }

  Future<void> _showEditDialog(int addr) async {
    final controller = TextEditingController(text: addr.toString());
    final newAddr = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('short_addr_manager.modify_title').tr(),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'short_addr_manager.new_address'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel').tr()),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null) {
                _showSnack('short_addr_manager.invalid_number'.tr());
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: const Text('OK').tr(),
          ),
        ],
      ),
    );
    if (newAddr != null && newAddr != addr) {
      await _renameAddress(addr, newAddr);
    }
  }

  Future<void> _confirmDelete(int addr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('short_addr_manager.delete_title').tr(),
        content: Text('short_addr_manager.delete_confirm'.tr(args: [addr.toString()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No').tr()),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes').tr()),
        ],
      ),
    );
    if (ok == true) {
      await _deleteAddress(addr);
    }
  }

  /// 拖拽排序并批量写入新地址顺序
  Future<void> _applyReorder(List<int> newOrder) async {
    if (_applyingOrder) return;
    if (!ConnectionManager.instance.ensureReadyForOperation()) return;
    int? startSlot = int.tryParse(_reorderStartCtrl.text) ?? 0;
    int? endSlot = int.tryParse(_reorderEndCtrl.text) ?? 63;
    if (startSlot < 0) startSlot = 0;
    if (endSlot > 63) endSlot = 63;
    if (startSlot > endSlot) {
      _showSnack('short_addr_manager.invalid_reorder_range'.tr());
      return;
    }
    // 生成需要应用的子列表与映射区段
    final window = newOrder.where((a) => a >= startSlot! && a <= endSlot!).toList();
    if (window.isEmpty) {
      _showSnack('short_addr_manager.no_change'.tr());
      return;
    }
    _cancelApply = false;
    setState(() {
      _applyingOrder = true;
    });
    // 思路: 找出需要变更的映射 old->new, 处理地址冲突
    final log = DaliLog.instance;
    Map<int, int> mapping = {}; // old -> new
    // 目标序列: 在指定窗口内按当前排列顺序映射到连续 startSlot..startSlot+len-1
    for (int i = 0; i < window.length; i++) {
      final actualAddr = window[i];
      final desired = startSlot + i;
      if (actualAddr != desired) mapping[actualAddr] = desired;
    }
    if (mapping.isEmpty) {
      _showSnack('short_addr_manager.no_change'.tr());
      setState(() {
        _applyingOrder = false;
      });
      return;
    }
    // 解决冲突: 如果 new 值被其它旧地址占用, 需要临时地址
    // 找一个未使用的临时地址 (0-63 范围) 不在当前 nor 目标集合
    Set<int> used = _addresses.toSet();
    int? temp;
    for (int t = 63; t >= 0; t--) {
      // 从高位向下找
      if (!used.contains(t) && !mapping.values.contains(t)) {
        temp = t;
        break;
      }
    }
    // 拓扑排序/循环检测
    Set<int> visited = {};
    Set<int> inStack = {};
    List<List<int>> cycles = [];
    void dfs(int node, List<int> path) {
      visited.add(node);
      inStack.add(node);
      final next = mapping[node];
      if (next != null) {
        if (!visited.contains(next)) {
          dfs(next, [...path, next]);
        } else if (inStack.contains(next)) {
          final idx = path.indexOf(next);
          cycles.add(path.sublist(idx));
        }
      }
      inStack.remove(node);
    }

    for (final k in mapping.keys) {
      if (!visited.contains(k)) dfs(k, [k]);
    }

    try {
      // 先处理循环
      for (final cycle in cycles) {
        if (_cancelApply) throw Exception('cancelled');
        if (temp == null) {
          _showSnack('short_addr_manager.temp_addr_fail'.tr());
          return;
        }
        final first = cycle.first;
        log.addLog('Reorder cycle: ${cycle.join("->")}');
        await widget.daliAddr.writeAddr(first, temp); // first -> temp
        int prev = first;
        for (int i = 1; i < cycle.length; i++) {
          final cur = cycle[i];
          if (_cancelApply) throw Exception('cancelled');
          await widget.daliAddr.writeAddr(cur, mapping[prev]!); // cur -> prev target
          prev = cur;
        }
        await widget.daliAddr.writeAddr(temp, mapping[prev]!); // temp -> last target
      }
      // 非循环部分: 拓扑顺序执行
      // 简化: 重复扫描直到无冲突
      for (final entry in mapping.entries) {
        if (_cancelApply) throw Exception('cancelled');
        if (cycles.any((c) => c.contains(entry.key))) continue; // 已处理
        if (_addresses.contains(entry.value) && !_addresses.contains(entry.key)) {
          // 目标被占用且原地址不存在(极少见)
          continue;
        }
        await widget.daliAddr.writeAddr(entry.key, entry.value);
      }
      await _startScan();
      _showSnack('short_addr_manager.reorder_success'.tr());
    } catch (e) {
      if (e.toString().contains('cancelled')) {
        _showSnack('short_addr_manager.reorder_cancelled'.tr());
      } else {
        _showSnack('short_addr_manager.reorder_fail'.tr(args: [e.toString()]));
      }
    }
    if (mounted) {
      setState(() {
        _applyingOrder = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // 扫描/停止 合并为一个切换按钮
            ElevatedButton.icon(
              onPressed: _scanning ? _stopScan : _startScan,
              icon: Icon(_scanning ? Icons.stop : Icons.search),
              label: Text(_scanning ? 'short_addr_manager.stop' : 'short_addr_manager.scan').tr(),
              style: _scanning
                  ? ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                  : null,
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 8),
            SizedBox(
              width: 55,
              child: TextField(
                controller: _scanStartCtrl,
                decoration: InputDecoration(labelText: 'S'),
                keyboardType: TextInputType.number,
                enabled: !_scanning,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 55,
              child: TextField(
                controller: _scanEndCtrl,
                decoration: InputDecoration(labelText: 'E'),
                keyboardType: TextInputType.number,
                enabled: !_scanning,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _addresses.isEmpty ? null : _toggleSelectionMode,
              icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
              label: Text(_selectionMode
                  ? 'short_addr_manager.selection_cancel'.tr()
                  : 'short_addr_manager.selection_mode'.tr()),
            ),
            if (_selectionMode) ...[
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectAll,
                child: Text(_selected.length == _addresses.length
                    ? 'short_addr_manager.unselect_all'.tr()
                    : 'short_addr_manager.select_all'.tr()),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: _selected.isEmpty ? null : _batchDelete,
                icon: const Icon(Icons.delete),
                label: Text('short_addr_manager.batch_delete'.tr()),
              ),
            ],
            const SizedBox(width: 16),
            Text('short_addr_manager.count'.tr(args: [_addresses.length.toString()])),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _addresses.isEmpty
              ? Center(
                  child: Text(_scanning
                      ? 'short_addr_manager.scanning'.tr()
                      : 'short_addr_manager.empty'.tr()))
              : Stack(children: [
                  ReorderableListView.builder(
                    itemCount: _addresses.length,
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 6,
                      color: Colors.transparent,
                      child: child,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _addresses.removeAt(oldIndex);
                        _addresses.insert(newIndex, item);
                      });
                    },
                    footer: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton.icon(
                        onPressed: () => _applyReorder(_addresses),
                        icon: const Icon(Icons.save),
                        label: Text('short_addr_manager.apply_order').tr(),
                      ),
                    ),
                    itemBuilder: (ctx, index) {
                      final addr = _addresses[index];
                      return ListTile(
                        key: ValueKey(addr),
                        leading: ReorderableDragStartListener(
                            index: index, child: const ReorderHandle()),
                        title: Row(
                          children: [
                            if (_selectionMode)
                              Checkbox(
                                value: _selected.contains(addr),
                                onChanged: (_) => _toggleSelect(addr),
                              ),
                            Expanded(
                                child: Text(
                                    'short_addr_manager.device_label'.tr(args: [addr.toString()]))),
                          ],
                        ),
                        subtitle:
                            Text('short_addr_manager.slot_label'.tr(args: [index.toString()])),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'short_addr_manager.modify'.tr(),
                              onPressed: () => _showEditDialog(addr),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Delete'.tr(),
                              onPressed: () => _confirmDelete(addr),
                            ),
                          ],
                        ),
                        onTap: () => widget.daliAddr.selectDevice(addr),
                      );
                    },
                  ),
                  if (_applyingOrder)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text('short_addr_manager.reorder_in_progress'.tr()),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() => _cancelApply = true);
                                },
                                icon: const Icon(Icons.cancel),
                                label: Text('short_addr_manager.cancel'.tr()),
                              )
                            ],
                          ),
                        ),
                      ),
                    )
                ]),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 70,
              child: TextField(
                controller: _reorderStartCtrl,
                decoration: InputDecoration(labelText: 'R-S'),
                keyboardType: TextInputType.number,
                enabled: !_applyingOrder,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 70,
              child: TextField(
                controller: _reorderEndCtrl,
                decoration: InputDecoration(labelText: 'R-E'),
                keyboardType: TextInputType.number,
                enabled: !_applyingOrder,
              ),
            ),
            const SizedBox(width: 12),
            Text('short_addr_manager.reorder_range_hint'.tr()),
          ],
        ),
      ],
    );
  }

  void _showSnack(String msg) {
    // 统一迁移为 Toast；根据关键字简单判断类型
    final lower = msg.toLowerCase();
    final toast = ToastManager();
    if (lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('无效') ||
        lower.contains('重复') ||
        lower.contains('失败')) {
      toast.showErrorToast(msg);
    } else if (lower.contains('success') ||
        lower.contains('完成') ||
        lower.contains('已删除') ||
        lower.contains('成功')) {
      toast.showDoneToast(msg);
    } else if (lower.contains('cancel') || lower.contains('取消')) {
      toast.showInfoToast(msg);
    } else {
      toast.showToast(msg);
    }
  }
}
