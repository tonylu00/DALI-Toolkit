import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../custom_keys/custom_key.dart';
import '../custom_keys/custom_key_store.dart';
import '../dali/sequence_store.dart';
import '../dali/sequence.dart';
import '../dali/dali.dart';
import '../connection/manager.dart';
import '../toast.dart';
import '../widgets/reorder_handle.dart';

/// 自定义按键页面
class CustomKeysPage extends StatefulWidget {
  final bool embedded;
  const CustomKeysPage({super.key, this.embedded = false});
  @override
  State<CustomKeysPage> createState() => _CustomKeysPageState();
}

class _CustomKeysPageState extends State<CustomKeysPage> {
  final repo = CustomKeyRepository.instance;
  final seqRepo = SequenceRepository.instance;
  bool loading = true;
  bool _editMode = false; // 编辑模式: 显示编辑/删除/排序列表
  double _gridButtonSize = 120; // 基础边长
  static const _kGridBtnSizeKey = 'custom_key_grid_btn_size';
  final Set<String> _activeToggle = {}; // 记录 toggleOnOff 激活的按键ID

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await seqRepo.load();
    await repo.load();
    final prefs = await SharedPreferences.getInstance();
    _gridButtonSize = prefs.getDouble(_kGridBtnSizeKey) ?? 120;
    setState(() => loading = false);
  }

  Future<void> _save() async => repo.save();

  Future<void> _createGroup() async {
    final name = await _inputDialog(title: 'custom_key.group.create'.tr());
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      final g = repo.createGroup(name.trim());
      repo.selectGroup(g.id);
    });
    await _save();
  }

  Future<void> _renameGroup() async {
    if (repo.currentGroup == null) return;
    final name =
        await _inputDialog(title: 'custom_key.group.rename'.tr(), initial: repo.currentGroup!.name);
    if (name == null || name.trim().isEmpty) return;
    setState(() => repo.renameGroup(repo.currentGroup!, name.trim()));
    await _save();
  }

  Future<void> _deleteGroup() async {
    if (repo.currentGroup == null) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('custom_key.group.delete'.tr()),
                content: Text('custom_key.group.delete_confirm'.tr()),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('sequence.cancel'.tr())),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('sequence.delete'.tr()))
                ]));
    if (ok != true) return;
    setState(() => repo.deleteGroup(repo.currentGroup!));
    await _save();
  }

  Future<String?> _inputDialog({required String title, String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: initial ?? '');
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: 'custom_key.group.name'.tr()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('sequence.cancel'.tr())),
            FilledButton(
                onPressed: () => Navigator.pop(context, ctrl.text),
                child: Text('sequence.save'.tr())),
          ],
        );
      },
    );
  }

  Future<void> _addOrEdit({CustomKeyDefinition? def}) async {
    final result = await showDialog<CustomKeyDefinition>(
        context: context,
        builder: (_) => _CustomKeyDialog(definition: def, sequences: seqRepo.sequences));
    if (result != null) {
      setState(() => def == null ? repo.add(result) : repo.replace(result));
      await _save();
    }
  }

  Future<void> _delete(CustomKeyDefinition def) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('custom_key.delete'.tr()),
                content: Text('custom_key.delete_confirm'.tr()),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('sequence.cancel'.tr())),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('sequence.delete'.tr()))
                ]));
    if (ok == true) {
      setState(() => repo.remove(def.id));
      await _save();
    }
  }

  Future<void> _execute(CustomKeyDefinition def) async {
    if (!ConnectionManager.instance.ensureReadyForOperation()) return;
    switch (def.actionType) {
      case CustomKeyActionType.runSequence:
        final seqId = def.params.get<String>('sequenceId');
        if (seqId == null) {
          ToastManager().showErrorToast('custom_key.no_sequence_selected'.tr());
          return;
        }
        final seq = seqRepo.sequences.firstWhere(
          (e) => e.id == seqId,
          orElse: () => CommandSequence(id: '', name: '', steps: []),
        );
        if (seq.id.isEmpty) {
          ToastManager().showErrorToast('custom_key.sequence_not_found'.tr());
          return;
        }
        final runner = SequenceRunner(seq);
        await runner.run();
        break;
      case CustomKeyActionType.allocateAddresses:
        await Dali.instance.addr!.allocateAllAddr();
        ToastManager().showInfoToast('custom_key.allocate_started'.tr());
        break;
      case CustomKeyActionType.resetAndAllocate:
        await Dali.instance.addr!.resetAndAllocAddr();
        ToastManager().showInfoToast('custom_key.reset_allocate_started'.tr());
        break;
      case CustomKeyActionType.on:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.on(a);
        }
        break;
      case CustomKeyActionType.off:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.off(a);
        }
        break;
      case CustomKeyActionType.setBright:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.setBright(a, def.params.getInt('level', 128));
        }
        break;
      case CustomKeyActionType.toScene:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.toScene(a, def.params.getInt('scene', 0));
        }
        break;
      case CustomKeyActionType.setScene:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.setScene(a, def.params.getInt('scene', 0));
        }
        break;
      case CustomKeyActionType.addToGroup:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.addToGroup(a, def.params.getInt('group', 0));
        }
        break;
      case CustomKeyActionType.removeFromGroup:
        {
          int a = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          if (def.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await Dali.instance.base!.removeFromGroup(a, def.params.getInt('group', 0));
        }
        break;
      case CustomKeyActionType.toggleOnOff:
        {
          int addr = def.params.getInt('addr', Dali.instance.base!.selectedAddress);
          final bool isGroup = def.params.data['isGroupAddr'] == 1 && addr != 127;
          if (isGroup) addr += 64;
          final active = _activeToggle.contains(def.id);
          if (active) {
            await Dali.instance.base!.off(addr);
            setState(() => _activeToggle.remove(def.id));
          } else {
            await Dali.instance.base!.on(addr);
            setState(() => _activeToggle.add(def.id));
          }
        }
        break;
    }
  }

  Future<void> _showSizeDialog() async {
    double temp = _gridButtonSize;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('custom_key.grid.size'.tr(), style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('custom_key.grid.size_hint'.tr()),
              const SizedBox(height: 12),
              StatefulBuilder(builder: (c, setS) {
                return Column(
                  children: [
                    Slider(
                      value: temp,
                      min: 80,
                      max: 200,
                      divisions: 12,
                      label: temp.toStringAsFixed(0),
                      onChanged: (v) => setS(() => temp = v),
                    ),
                    Text('${temp.toStringAsFixed(0)} px')
                  ],
                );
              })
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('sequence.cancel'.tr())),
          FilledButton(
              onPressed: () async {
                setState(() => _gridButtonSize = temp);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setDouble(_kGridBtnSizeKey, _gridButtonSize);
                Navigator.pop(context);
              },
              child: Text('sequence.save'.tr()))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final groupBar = Row(children: [
      Expanded(
          child: DropdownButton<String>(
              isExpanded: true,
              value: repo.currentGroup?.id,
              items: repo.groups
                  .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => repo.selectGroup(v));
                _activeToggle.clear(); // 切换组重置
              })),
      IconButton(
          onPressed: _createGroup,
          icon: const Icon(Icons.playlist_add),
          tooltip: 'custom_key.group.create'.tr()),
      IconButton(
          onPressed: _renameGroup,
          icon: const Icon(Icons.edit),
          tooltip: 'custom_key.group.rename'.tr()),
      IconButton(
          onPressed: _deleteGroup,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'custom_key.group.delete'.tr())
    ]);
    final content = Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(children: [
            groupBar,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text('custom_key.page_title'.tr(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              // 新增：编辑模式切换
              IconButton(
                  tooltip: _editMode ? 'sequence.save'.tr() : 'Edit'.tr(),
                  onPressed: () => setState(() => _editMode = !_editMode),
                  icon: Icon(_editMode ? Icons.check : Icons.edit_square)),
              IconButton(
                  onPressed: () => _addOrEdit(),
                  tooltip: 'custom_key.add'.tr(),
                  icon: const Icon(Icons.add_circle_outline))
            ])
          ])),
      Expanded(
          child: repo.keys.isEmpty
              ? Center(child: Text('custom_key.empty'.tr()))
              : _editMode
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: repo.keys.length,
                      onReorder: (o, n) async {
                        setState(() => repo.reorder(o, n));
                        await _save();
                      },
                      itemBuilder: (c, i) {
                        final k = repo.keys[i];
                        final summary = _actionSummary(k);
                        final isToggleActive = _activeToggle.contains(k.id);
                        return ListTile(
                            key: ValueKey(k.id),
                            tileColor: k.actionType == CustomKeyActionType.toggleOnOff &&
                                    isToggleActive
                                ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6)
                                : null,
                            title: Text(k.actionType == CustomKeyActionType.toggleOnOff
                                ? '$summary (${isToggleActive ? 'ON'.tr() : 'OFF'.tr()})'
                                : summary),
                            subtitle: k.name.isNotEmpty
                                ? Text(k.name, style: Theme.of(context).textTheme.bodySmall)
                                : null,
                            leading: const Icon(Icons.smart_button_outlined),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  onPressed: () => _addOrEdit(def: k),
                                  icon: const Icon(Icons.edit, size: 18)),
                              IconButton(
                                  onPressed: () => _delete(k),
                                  icon: const Icon(Icons.delete, size: 18)),
                              ReorderableDragStartListener(index: i, child: const ReorderHandle())
                            ]),
                            onTap: () => _execute(k));
                      })
                  : LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final cross = width ~/ (_gridButtonSize + 24); // 24 近似包含边距/间距
                      final crossAxisCount = cross.clamp(1, 8);
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1,
                        ),
                        itemCount: repo.keys.length,
                        itemBuilder: (c, i) {
                          final k = repo.keys[i];
                          final summary = _actionSummary(k);
                          final isToggleActive = _activeToggle.contains(k.id);
                          return SizedBox(
                            width: _gridButtonSize,
                            height: _gridButtonSize,
                            child: ElevatedButton(
                              onPressed: () => _execute(k),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.all(8),
                                backgroundColor: k.actionType == CustomKeyActionType.toggleOnOff &&
                                        isToggleActive
                                    ? Theme.of(context).colorScheme.secondaryContainer
                                    : null,
                                foregroundColor: k.actionType == CustomKeyActionType.toggleOnOff &&
                                        isToggleActive
                                    ? Theme.of(context).colorScheme.onSecondaryContainer
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    summary,
                                    textAlign: TextAlign.center,
                                    style:
                                        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (k.actionType == CustomKeyActionType.toggleOnOff) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      isToggleActive ? 'ON'.tr() : 'OFF'.tr(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: k.actionType == CustomKeyActionType.toggleOnOff &&
                                                isToggleActive
                                            ? Theme.of(context).colorScheme.onSecondaryContainer
                                            : Theme.of(context).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                  ],
                                  if (k.name.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(k.name,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(fontSize: 11, color: Colors.white70),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ]
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }))
    ]);
    if (widget.embedded) return content;
    return Scaffold(
        appBar: AppBar(title: Text('custom_key.page_title'.tr()), actions: [
          if (!_editMode)
            IconButton(
                tooltip: 'custom_key.grid.size'.tr(),
                onPressed: _showSizeDialog,
                icon: const Icon(Icons.aspect_ratio))
        ]),
        body: content);
  }

  String _actionSummary(CustomKeyDefinition k) {
    String addrStr(int v) => v == 127 ? 'sequence.field.broadcast'.tr() : v.toString();
    final bool isGroupAddr = k.params.data['isGroupAddr'] == 1 && k.params.getInt('addr') != 127;
    switch (k.actionType) {
      case CustomKeyActionType.runSequence:
        final seqId = k.params.get<String>('sequenceId');
        final seq = seqRepo.sequences.firstWhere(
          (e) => e.id == seqId,
          orElse: () => CommandSequence(id: '', name: '', steps: []),
        );
        return 'custom_key.summary.run_sequence'
            .tr(namedArgs: {'name': seq.name.isEmpty ? '-' : seq.name});
      case CustomKeyActionType.allocateAddresses:
        return 'custom_key.summary.allocate'.tr();
      case CustomKeyActionType.resetAndAllocate:
        return 'custom_key.summary.reset_allocate'.tr();
      case CustomKeyActionType.on:
        {
          String s =
              'sequence.summary.on'.tr(namedArgs: {'addr': addrStr(k.params.getInt('addr'))});
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.off:
        {
          String s =
              'sequence.summary.off'.tr(namedArgs: {'addr': addrStr(k.params.getInt('addr'))});
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.setBright:
        {
          String s = 'sequence.summary.setBright'.tr(namedArgs: {
            'addr': addrStr(k.params.getInt('addr')),
            'level': k.params.getInt('level').toString()
          });
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.toScene:
        {
          String s = 'sequence.summary.toScene'.tr(namedArgs: {
            'addr': addrStr(k.params.getInt('addr')),
            'scene': k.params.getInt('scene').toString()
          });
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.setScene:
        {
          String s = 'sequence.summary.setScene'.tr(namedArgs: {
            'addr': addrStr(k.params.getInt('addr')),
            'scene': k.params.getInt('scene').toString()
          });
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.addToGroup:
        {
          String s = 'sequence.summary.addToGroup'.tr(namedArgs: {
            'addr': addrStr(k.params.getInt('addr')),
            'group': k.params.getInt('group').toString()
          });
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.removeFromGroup:
        {
          String s = 'sequence.summary.removeFromGroup'.tr(namedArgs: {
            'addr': addrStr(k.params.getInt('addr')),
            'group': k.params.getInt('group').toString()
          });
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
      case CustomKeyActionType.toggleOnOff:
        {
          String s = 'custom_key.summary.toggleOnOff'
              .tr(namedArgs: {'addr': addrStr(k.params.getInt('addr'))});
          if (isGroupAddr) {
            s = s
                .replaceAll('地址 ', '组 ')
                .replaceAll('Addr ', 'Group ')
                .replaceAll('Address ', 'Group ');
          }
          return s;
        }
    }
  }
}

class _CustomKeyDialog extends StatefulWidget {
  final CustomKeyDefinition? definition;
  final List<CommandSequence> sequences;
  const _CustomKeyDialog({required this.definition, required this.sequences});
  @override
  State<_CustomKeyDialog> createState() => _CustomKeyDialogState();
}

class _CustomKeyDialogState extends State<_CustomKeyDialog> {
  late TextEditingController _nameCtrl;
  late CustomKeyActionType _actionType;
  String? _selectedSequenceId;
  final Map<String, TextEditingController> _paramCtrls = {};
  bool _broadcast = false;
  bool _groupAddr = false; // 是否组地址 (addr + 64)

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.definition?.name ?? '');
    _actionType = widget.definition?.actionType ?? CustomKeyActionType.runSequence;
    _selectedSequenceId = widget.definition?.params.get('sequenceId');
    _initParamCtrls();
  }

  void _initParamCtrls() {
    _paramCtrls.clear();
    final existing = widget.definition?.params.data ?? {};
    for (final m in customKeyActionMeta(_actionType)) {
      _paramCtrls[m.key] = TextEditingController(text: existing[m.key]?.toString() ?? '');
    }
    if (_paramCtrls.containsKey('addr')) {
      _broadcast = _paramCtrls['addr']!.text == '127';
      _groupAddr = (existing['isGroupAddr'] == 1 || existing['isGroupAddr'] == true) && !_broadcast;
    } else {
      _broadcast = false;
      _groupAddr = false;
    }
  }

  void _changeType(CustomKeyActionType t) {
    setState(() {
      _actionType = t;
      _initParamCtrls();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = customKeyActionMeta(_actionType);
    return AlertDialog(
      title: Text(widget.definition == null ? 'custom_key.add'.tr() : 'custom_key.edit'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: 'sequence.field.remark'.tr(),
                    hintText: 'sequence.field.remark'.tr()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CustomKeyActionType>(
                value: _actionType,
                decoration: InputDecoration(labelText: 'custom_key.field.action'.tr()),
                items: CustomKeyActionType.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label())))
                    .toList(),
                onChanged: (v) => _changeType(v!),
              ),
              const SizedBox(height: 12),
              if (_actionType == CustomKeyActionType.runSequence)
                DropdownButtonFormField<String>(
                  value: _selectedSequenceId,
                  decoration: InputDecoration(labelText: 'custom_key.field.sequence'.tr()),
                  items: widget.sequences
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSequenceId = v),
                ),
              if (_actionType != CustomKeyActionType.runSequence && fields.isNotEmpty)
                Column(
                  children: [
                    for (final f in fields)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _paramCtrls[f.key],
                                keyboardType: TextInputType.number,
                                enabled: !(f.key == 'addr' && _broadcast),
                                decoration: InputDecoration(labelText: f.labelKey.tr()),
                              ),
                            ),
                            if (f.key == 'addr') ...[
                              const SizedBox(width: 8),
                              Column(
                                children: [
                                  Row(children: [
                                    Checkbox(
                                      value: _groupAddr,
                                      onChanged: _broadcast
                                          ? null
                                          : (v) {
                                              setState(() {
                                                final newVal = v ?? false;
                                                if (_groupAddr != newVal) {
                                                  _paramCtrls['addr']!.clear();
                                                }
                                                _groupAddr = newVal;
                                              });
                                            },
                                    ),
                                    Text('sequence.field.groupAddr'.tr()),
                                  ])
                                ],
                              ),
                              const SizedBox(width: 8),
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _broadcast,
                                        onChanged: (v) {
                                          setState(() {
                                            _broadcast = v ?? false;
                                            if (_broadcast) {
                                              _paramCtrls['addr']!.text = '127';
                                              _groupAddr = false; // 互斥
                                            } else {
                                              _paramCtrls['addr']!.clear();
                                            }
                                          });
                                        },
                                      ),
                                      Text('sequence.field.broadcast'.tr()),
                                    ],
                                  ),
                                ],
                              ),
                            ]
                          ],
                        ),
                      ),
                  ],
                ),
              if (_actionType == CustomKeyActionType.allocateAddresses ||
                  _actionType == CustomKeyActionType.resetAndAllocate)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _actionType == CustomKeyActionType.allocateAddresses
                        ? 'custom_key.help.allocate'.tr()
                        : 'custom_key.help.reset_allocate'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('sequence.cancel'.tr())),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            // 备注可选，不再强制校验
            if (_actionType == CustomKeyActionType.runSequence && _selectedSequenceId == null) {
              ToastManager().showErrorToast('custom_key.no_sequence_selected'.tr());
              return;
            }
            // 参数解析
            final params = <String, dynamic>{};
            if (_actionType == CustomKeyActionType.runSequence) {
              params['sequenceId'] = _selectedSequenceId;
            } else {
              for (final f in fields) {
                final txtRaw = _paramCtrls[f.key]?.text.trim() ?? '';
                String txt = txtRaw;
                if (f.key == 'addr' && _broadcast) {
                  txt = '127';
                }
                if (txt.isEmpty) {
                  ToastManager().showErrorToast('sequence.validation.field_required'.tr());
                  return;
                }
                final v = int.tryParse(txt);
                if (v == null) {
                  ToastManager().showErrorToast('sequence.validation.field_required'.tr());
                  return;
                }
                if ((f.min != null && v < f.min!) || (f.max != null && v > f.max!)) {
                  ToastManager().showErrorToast('sequence.validation.field_required'.tr());
                  return;
                }
                if (f.key == 'addr' && !_broadcast) {
                  if (_groupAddr) {
                    if (v < 0 || v > 15) {
                      ToastManager().showErrorToast('sequence.validation.field_required'.tr());
                      return;
                    }
                  } else {
                    if (v < 0 || v > 63) {
                      ToastManager().showErrorToast('sequence.validation.field_required'.tr());
                      return;
                    }
                  }
                }
                params[f.key] = v;
              }
            }
            if (_broadcast) {
              params['addr'] = 127;
            }
            if (_groupAddr && !_broadcast && params.containsKey('addr')) {
              params['isGroupAddr'] = 1; // 标记执行时 +64
            }
            final def = CustomKeyDefinition(
              id: widget.definition?.id ?? Random().nextInt(1 << 32).toString(),
              name: name,
              actionType: _actionType,
              params: CustomKeyParams(params),
              order: widget.definition?.order ?? DateTime.now().millisecondsSinceEpoch,
            );
            Navigator.pop(context, def);
          },
          child: Text('sequence.save'.tr()),
        ),
      ],
    );
  }
}
