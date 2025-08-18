import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../dali/sequence.dart';
import '../dali/sequence_store.dart';

/// 指令序列编辑页面
class SequenceEditorPage extends StatefulWidget {
  const SequenceEditorPage({super.key});
  @override
  State<SequenceEditorPage> createState() => _SequenceEditorPageState();
}

class _SequenceEditorPageState extends State<SequenceEditorPage> {
  final repo = SequenceRepository.instance;
  CommandSequence? current;
  SequenceRunner? runner;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await repo.load();
    if (repo.sequences.isEmpty) {
      final s = _newSequence();
      repo.add(s);
      await repo.save();
    }
    current = repo.sequences.first;
    runner = SequenceRunner(current!)..addListener(() => setState(() {}));
    setState(() => loading = false);
  }

  @override
  void dispose() {
    runner?.removeListener(() {});
    super.dispose();
  }

  CommandSequence _newSequence() {
    final id = Random().nextInt(1 << 32).toString();
    final name = 'sequence.sequence.default_name'.tr(args: ['${repo.sequences.length + 1}']);
    return CommandSequence(id: id, name: name);
  }

  Future<void> _selectSequence(CommandSequence s) async {
    if (current?.id == s.id) return;
    setState(() {
      current = s;
      runner = SequenceRunner(current!)..addListener(() => setState(() {}));
    });
  }

  Future<void> _createSequence() async {
    final s = _newSequence();
    setState(() {
      repo.add(s);
      current = s;
      runner = SequenceRunner(current!)..addListener(() => setState(() {}));
    });
    await repo.save();
  }

  Future<void> _renameSequence(CommandSequence s) async {
    final ctrl = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('sequence.sequence.rename'.tr()),
        content: TextField(
            controller: ctrl, decoration: InputDecoration(labelText: 'sequence.field.name'.tr())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('sequence.cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text('sequence.save'.tr()))
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => s.name = name);
      repo.replace(s);
      await repo.save();
    }
  }

  Future<void> _deleteSequence(CommandSequence s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('sequence.sequence.delete'.tr()),
        content: Text('sequence.sequence.delete_confirm'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: Text('sequence.cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: Text('sequence.delete'.tr()))
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        repo.remove(s.id);
        if (current?.id == s.id) {
          current = repo.sequences.isEmpty ? null : repo.sequences.first;
          if (current != null) {
            runner = SequenceRunner(current!)..addListener(() => setState(() {}));
          } else {
            runner = null;
          }
        }
      });
      await repo.save();
      if (repo.sequences.isEmpty) {
        await _createSequence();
      }
    }
  }

  void _addStep() async {
    if (current == null) return;
    final step = await showDialog<SequenceStep>(
      context: context,
      builder: (_) => StepDialog(),
    );
    if (step != null) {
      setState(() => current!.steps.add(step));
      repo.replace(current!);
      await repo.save();
    }
  }

  void _editStep(int index) async {
    if (current == null) return;
    final step = current!.steps[index];
    final edited = await showDialog<SequenceStep>(
      context: context,
      builder: (_) => StepDialog(step: step.copy()),
    );
    if (edited != null) {
      setState(() => current!.steps[index] = edited);
      repo.replace(current!);
      await repo.save();
    }
  }

  void _deleteStep(int index) async {
    if (current == null) return;
    setState(() => current!.steps.removeAt(index));
    repo.replace(current!);
    await repo.save();
  }

  Future<void> _run() async {
    await runner?.run();
  }

  void _stop() {
    runner?.stop();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final seq = current!;
    final media = MediaQuery.of(context);
    final isNarrow = media.size.width < 600; // 自适应阈值
    return Scaffold(
      appBar: AppBar(
        title: Text('sequence.editor.title'.tr()),
        actions: [
          // 宽屏仍在顶部添加步骤；窄屏改为浮动按钮
          if (!isNarrow)
            IconButton(
                onPressed: _addStep,
                tooltip: 'sequence.add_step'.tr(),
                icon: const Icon(Icons.add)),
          if (runner?.isRunning == true)
            IconButton(
                onPressed: _stop, tooltip: 'sequence.stop'.tr(), icon: const Icon(Icons.stop))
          else
            IconButton(
                onPressed: _run, tooltip: 'sequence.run'.tr(), icon: const Icon(Icons.play_arrow)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') {
                _renameSequence(seq);
              } else if (v == 'delete') {
                _deleteSequence(seq);
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(value: 'rename', child: Text('sequence.sequence.rename'.tr())),
              PopupMenuItem(value: 'delete', child: Text('sequence.sequence.delete'.tr())),
            ],
          )
        ],
      ),
      body: isNarrow ? _buildNarrowBody(seq) : _buildWideBody(seq),
      floatingActionButton: isNarrow
          ? FloatingActionButton(
              onPressed: _addStep,
              tooltip: 'sequence.add_step'.tr(),
              child: const Icon(Icons.add),
            )
          : null,
      // 原浮动添加步骤按钮移除，顶部已替换为添加步骤
    );
  }

  Widget _buildWideBody(CommandSequence seq) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('sequence.sequences'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(onPressed: _createSequence, icon: const Icon(Icons.add, size: 20))
                  ],
                ),
              ),
              Expanded(child: _sequenceList(seq))
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _stepsList(seq)),
      ],
    );
  }

  Widget _buildNarrowBody(CommandSequence seq) {
    return Column(
      children: [
        // 顶部使用下拉选择序列 + 新建按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: seq.id,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'sequence.sequences'.tr()),
                  items: repo.sequences
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) {
                    final target = repo.sequences.firstWhere((e) => e.id == v);
                    _selectSequence(target);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                  tooltip: 'sequence.sequence.new'.tr(),
                  onPressed: _createSequence,
                  icon: const Icon(Icons.add_circle_outline))
            ],
          ),
        ),
        // 步骤列表
        Expanded(child: _stepsList(seq)),
      ],
    );
  }

  Widget _sequenceList(CommandSequence seq) {
    return ListView.builder(
      itemCount: repo.sequences.length,
      itemBuilder: (c, i) {
        final s = repo.sequences[i];
        final selected = s.id == seq.id;
        return ListTile(
          selected: selected,
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _selectSequence(s),
          trailing: selected && runner?.isRunning == true
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        );
      },
    );
  }

  Widget _stepsList(CommandSequence seq) {
    if (seq.steps.isEmpty) {
      return Center(child: Text('sequence.no_steps'.tr()));
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: seq.steps.length,
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = seq.steps.removeAt(oldIndex);
          seq.steps.insert(newIndex, item);
        });
        repo.replace(seq);
        await repo.save();
      },
      itemBuilder: (context, index) {
        final s = seq.steps[index];
        final meta = _paramsSummary(s);
        final running = runner?.isRunning == true && runner?.currentIndex == index;
        return Container(
            key: ValueKey(s.id),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: () {
                      final c = Theme.of(context).dividerColor;
                      final baseAlpha = c.a; // 0-255
                      final newAlpha = (baseAlpha * 0.3).clamp(0, 255).toInt();
                      return c.withValues(alpha: newAlpha / 255);
                    }(),
                    width: 0.5),
              ),
            ),
            child: ListTile(
              dense: MediaQuery.of(context).size.width < 600,
              leading: running
                  ? const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('${index + 1}'),
              title: Text(s.type.label(), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(meta,
                  style: TextStyle(
                      color: () {
                        final c = Theme.of(context).textTheme.bodySmall?.color;
                        if (c == null) return null;
                        final baseAlpha = c.a; // 0-255
                        final newAlpha = (baseAlpha * 0.6).clamp(0, 255).toInt();
                        return c.withValues(alpha: newAlpha / 255);
                      }(),
                      fontSize: 12)),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editStep(index),
                      icon: const Icon(Icons.edit, size: 18)),
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _deleteStep(index),
                      icon: const Icon(Icons.delete, size: 18)),
                  const Icon(Icons.drag_handle),
                ],
              ),
            ));
      },
    );
  }

  String _paramsSummary(SequenceStep s) {
    String base;
    // 识别广播地址 (127) 并替换展示
    String addrVal(int v) {
      if (v == 127 && s.type != DaliCommandType.modifyShortAddress) {
        return 'sequence.field.broadcast'.tr();
      }
      return v.toString();
    }

    final bool isBroadcast =
        s.type != DaliCommandType.modifyShortAddress && s.params.getInt('addr') == 127;
    switch (s.type) {
      case DaliCommandType.setBright:
        base = 'sequence.summary.setBright'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'level': s.params.getInt('level').toString(),
        });
        break;
      case DaliCommandType.on:
        base = 'sequence.summary.on'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
        });
        break;
      case DaliCommandType.off:
        base = 'sequence.summary.off'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
        });
        break;
      case DaliCommandType.toScene:
        base = 'sequence.summary.toScene'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'scene': s.params.getInt('scene').toString(),
        });
        break;
      case DaliCommandType.setScene:
        base = 'sequence.summary.setScene'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'scene': s.params.getInt('scene').toString(),
        });
        break;
      case DaliCommandType.removeScene:
        base = 'sequence.summary.removeScene'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'scene': s.params.getInt('scene').toString(),
        });
        break;
      case DaliCommandType.addToGroup:
        base = 'sequence.summary.addToGroup'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'group': s.params.getInt('group').toString(),
        });
        break;
      case DaliCommandType.removeFromGroup:
        base = 'sequence.summary.removeFromGroup'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'group': s.params.getInt('group').toString(),
        });
        break;
      case DaliCommandType.setFadeTime:
        base = 'sequence.summary.setFadeTime'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'value': s.params.getInt('value').toString(),
        });
        break;
      case DaliCommandType.setFadeRate:
        base = 'sequence.summary.setFadeRate'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
          'value': s.params.getInt('value').toString(),
        });
        break;
      case DaliCommandType.wait:
        base = 'sequence.summary.wait'.tr(namedArgs: {
          'ms': s.params.getInt('ms').toString(),
        });
        break;
      case DaliCommandType.modifyShortAddress:
        base = 'sequence.summary.modifyShortAddress'.tr(namedArgs: {
          'oldAddr': s.params.getInt('oldAddr').toString(),
          'newAddr': s.params.getInt('newAddr').toString(),
        });
        break;
      case DaliCommandType.deleteShortAddress:
        base = 'sequence.summary.deleteShortAddress'.tr(namedArgs: {
          'addr': addrVal(s.params.getInt('addr')),
        });
        break;
    }
    if (isBroadcast) {
      final bLabel = 'sequence.field.broadcast'.tr();
      // 去掉中文“地址 ”或英文“Addr ”/"Address " 前缀
      base = base
          .replaceAll('地址 $bLabel', bLabel)
          .replaceAll('Addr $bLabel', bLabel)
          .replaceAll('Address $bLabel', bLabel);
    }
    if (s.remark != null && s.remark!.isNotEmpty) {
      return '$base  | ${s.remark}';
    }
    return base;
  }
}

class StepDialog extends StatefulWidget {
  final SequenceStep? step;
  const StepDialog({super.key, this.step});

  @override
  State<StepDialog> createState() => _StepDialogState();
}

class _StepDialogState extends State<StepDialog> {
  late DaliCommandType _type;
  final TextEditingController _remarkCtrl = TextEditingController();
  Map<String, TextEditingController> paramCtrls = {};
  bool _broadcast = false; // 是否广播（addr=127）

  @override
  void initState() {
    super.initState();
    _type = widget.step?.type ?? DaliCommandType.setBright;
    _remarkCtrl.text = widget.step?.remark ?? '';
    _initParamControllers();
  }

  void _initParamControllers() {
    paramCtrls.clear();
    final existing = widget.step?.params.data ?? {};
    for (final f in commandMeta(_type)) {
      final c = TextEditingController(text: existing[f.key]?.toString() ?? '');
      paramCtrls[f.key] = c;
    }
    // 如果已有 addr=127 则自动勾选广播
    if (paramCtrls.containsKey('addr')) {
      if (paramCtrls['addr']!.text == '127') {
        _broadcast = true;
      } else {
        _broadcast = false;
      }
    } else {
      _broadcast = false;
    }
  }

  void _changeType(DaliCommandType t) {
    setState(() {
      _type = t;
      _initParamControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('sequence.edit_step'.tr()),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<DaliCommandType>(
                value: _type,
                items: DaliCommandType.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label())))
                    .toList(),
                onChanged: (v) => _changeType(v!),
                decoration: InputDecoration(labelText: 'sequence.field.name'.tr()),
              ),
              TextField(
                controller: _remarkCtrl,
                decoration: InputDecoration(labelText: 'sequence.field.remark'.tr()),
              ),
              const SizedBox(height: 12),
              ...commandMeta(_type).map((f) {
                final isAddrField = f.key == 'addr';
                final showBroadcast = isAddrField && _type != DaliCommandType.modifyShortAddress;
                if (isAddrField) {
                  // 如果是广播且当前勾选，锁定为 127
                  if (_broadcast) {
                    paramCtrls[f.key]!.text = '127';
                  }
                }
                final textField = TextField(
                  controller: paramCtrls[f.key],
                  enabled: !(isAddrField && _broadcast),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                );
                if (showBroadcast) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: textField),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _broadcast,
                                  onChanged: (v) {
                                    setState(() {
                                      _broadcast = v ?? false;
                                      if (_broadcast) {
                                        paramCtrls[f.key]!.text = '127';
                                      } else {
                                        // 取消选中清空
                                        paramCtrls[f.key]!.clear();
                                      }
                                    });
                                  },
                                ),
                                Text('sequence.field.broadcast'.tr()),
                              ],
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: textField,
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('sequence.cancel'.tr())),
        FilledButton(
          onPressed: () {
            final params = <String, dynamic>{};
            bool missing = false;
            // 哪些字段允许为空: modifyShortAddress 的 oldAddr 可以为空(表示使用当前选中)
            Set<String> optional = {};
            if (_type == DaliCommandType.modifyShortAddress) {
              optional.add('oldAddr');
            }
            for (final f in commandMeta(_type)) {
              final c = paramCtrls[f.key]!;
              final txt = c.text.trim();
              if (txt.isEmpty && !optional.contains(f.key)) {
                missing = true;
                break;
              }
              if (txt.isNotEmpty) {
                params[f.key] = int.tryParse(txt) ?? txt;
              }
            }
            if (_broadcast) {
              // 强制广播地址
              params['addr'] = 127;
            }
            if (missing) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('sequence.validation.field_required'.tr())));
              return;
            }
            final step = SequenceStep(
              id: widget.step?.id ?? Random().nextInt(1 << 32).toString(),
              remark: _remarkCtrl.text,
              type: _type,
              params: DaliCommandParams(params),
            );
            Navigator.pop(context, step);
          },
          child: Text('sequence.save'.tr()),
        )
      ],
    );
  }
}
