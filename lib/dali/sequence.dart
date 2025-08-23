import 'dart:async';
import 'package:flutter/material.dart';
import 'log.dart';
import 'dali.dart';
import 'base.dart';
import 'addr.dart';
import 'package:easy_localization/easy_localization.dart';

/// 命令类型：后续可继续补充
enum DaliCommandType {
  setBright,
  on,
  off,
  toScene,
  setScene,
  removeScene,
  addToGroup,
  removeFromGroup,
  setFadeTime,
  setFadeRate,
  wait, // 纯延时
  modifyShortAddress, // 修改短地址
  deleteShortAddress, // 删除短地址
}

extension DaliCommandTypeI18n on DaliCommandType {
  String i18nKey() => 'sequence.cmd.$name';
  String label() => i18nKey().tr();
}

/// 命令参数存储（统一为 Map）
class DaliCommandParams {
  final Map<String, dynamic> data;
  DaliCommandParams([Map<String, dynamic>? d]) : data = d ?? {};
  T? get<T>(String k) => data[k] as T?;
  int getInt(String k, [int def = 0]) => (data[k] as int?) ?? def;
  DaliCommandParams copy() => DaliCommandParams({...data});
  Map<String, dynamic> toJson() => data;
  factory DaliCommandParams.fromJson(Map<String, dynamic> json) => DaliCommandParams(json);
}

class SequenceStep {
  String id; // uuid 或 时间戳
  String? remark; // 用户备注
  DaliCommandType type;
  DaliCommandParams params;
  SequenceStep({required this.id, required this.type, this.remark, DaliCommandParams? params})
      : params = params ?? DaliCommandParams();

  SequenceStep copy() => SequenceStep(id: id, type: type, remark: remark, params: params.copy());

  Map<String, dynamic> toJson() => {
        'id': id,
        'remark': remark,
        'type': type.name,
        'params': params.toJson(),
      };
  factory SequenceStep.fromJson(Map<String, dynamic> json) => SequenceStep(
        id: json['id'],
        type: DaliCommandType.values
            .firstWhere((e) => e.name == json['type'], orElse: () => DaliCommandType.setBright),
        remark: json['remark'],
        params: DaliCommandParams.fromJson((json['params'] as Map).cast<String, dynamic>()),
      );
}

class CommandSequence {
  String id;
  String name;
  List<SequenceStep> steps;
  CommandSequence({required this.id, required this.name, List<SequenceStep>? steps})
      : steps = steps ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((e) => e.toJson()).toList(),
      };
  factory CommandSequence.fromJson(Map<String, dynamic> json) => CommandSequence(
        id: json['id'],
        name: json['name'],
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => SequenceStep.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// 序列执行器
class SequenceRunner with ChangeNotifier {
  final CommandSequence sequence;
  bool _isRunning = false;
  int _currentIndex = -1;
  bool get isRunning => _isRunning;
  int get currentIndex => _currentIndex;
  DaliBase get base => Dali.instance.base!;
  DaliAddr get addr => Dali.instance.addr!;

  SequenceRunner(this.sequence);

  Future<void> run() async {
    if (_isRunning) return;
    // 连接检查
    try {
      final cm = Dali.instance.cm;
      if (!cm.connection.isDeviceConnected()) {
        DaliLog.instance.debugLog('[SequenceRunner] Connection not established, abort run');
        return;
      }
    } catch (_) {}
    _isRunning = true;
    _currentIndex = -1;
    notifyListeners();
    for (int i = 0; i < sequence.steps.length; i++) {
      if (!_isRunning) break;
      _currentIndex = i;
      notifyListeners();
      final step = sequence.steps[i];
      try {
        await _executeStep(step);
      } catch (e) {
        DaliLog.instance.debugLog('Sequence step error: $e');
        break;
      }
    }
    _isRunning = false;
    _currentIndex = -1;
    notifyListeners();
  }

  void stop() {
    if (_isRunning) {
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> _executeStep(SequenceStep step) async {
    switch (step.type) {
      case DaliCommandType.setBright:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          final v = step.params.getInt('level', 128);
          await base.setBright(a, v);
        }
        break;
      case DaliCommandType.on:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.on(a);
        }
        break;
      case DaliCommandType.off:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.off(a);
        }
        break;
      case DaliCommandType.toScene:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.toScene(a, step.params.getInt('scene', 0));
        }
        break;
      case DaliCommandType.setScene:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.setScene(a, step.params.getInt('scene', 0));
        }
        break;
      case DaliCommandType.removeScene:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.removeScene(a, step.params.getInt('scene', 0));
        }
        break;
      case DaliCommandType.addToGroup:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.addToGroup(a, step.params.getInt('group', 0));
        }
        break;
      case DaliCommandType.removeFromGroup:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.removeFromGroup(a, step.params.getInt('group', 0));
        }
        break;
      case DaliCommandType.setFadeTime:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.setFadeTime(a, step.params.getInt('value', 0));
        }
        break;
      case DaliCommandType.setFadeRate:
        {
          int a = step.params.getInt('addr', base.selectedAddress);
          if (step.params.data['isGroupAddr'] == 1 && a != 127) a += 64;
          await base.setFadeRate(a, step.params.getInt('value', 0));
        }
        break;
      case DaliCommandType.wait:
        final ms = step.params.getInt('ms', 500);
        await Future.delayed(Duration(milliseconds: ms));
        break;
      case DaliCommandType.modifyShortAddress:
        // 参数: oldAddr(可选, 默认当前 selectedAddress), newAddr (必填)
        final oldAddr = step.params.getInt('oldAddr', base.selectedAddress);
        final newAddr = step.params.getInt('newAddr', oldAddr);
        if (newAddr != oldAddr) {
          await Dali.instance.addr!.writeAddr(oldAddr, newAddr);
        }
        break;
      case DaliCommandType.deleteShortAddress:
        final a = step.params.getInt('addr', base.selectedAddress);
        await Dali.instance.addr!.removeAddr(a);
        break;
    }
  }
}

/// 工具：根据命令类型给出默认可编辑参数元数据（用于动态表单）
class CommandMetaField {
  final String key;
  final String label;
  final String hint;
  final int? min;
  final int? max;
  CommandMetaField(this.key, this.label, {this.hint = '', this.min, this.max});
}

List<CommandMetaField> commandMeta(DaliCommandType t) {
  switch (t) {
    case DaliCommandType.setBright:
      return [
        CommandMetaField('addr', 'sequence.field.addr'.tr()),
        CommandMetaField('level', 'sequence.field.level'.tr(), min: 0, max: 254)
      ];
    case DaliCommandType.on:
    case DaliCommandType.off:
      return [CommandMetaField('addr', 'sequence.field.addr'.tr())];
    case DaliCommandType.toScene:
    case DaliCommandType.setScene:
    case DaliCommandType.removeScene:
      return [
        CommandMetaField('addr', 'sequence.field.addr'.tr()),
        CommandMetaField('scene', 'sequence.field.scene'.tr(), min: 0, max: 15)
      ];
    case DaliCommandType.addToGroup:
    case DaliCommandType.removeFromGroup:
      return [
        CommandMetaField('addr', 'sequence.field.addr'.tr()),
        CommandMetaField('group', 'sequence.field.group'.tr(), min: 0, max: 15)
      ];
    case DaliCommandType.setFadeTime:
    case DaliCommandType.setFadeRate:
      return [
        CommandMetaField('addr', 'sequence.field.addr'.tr()),
        CommandMetaField('value', 'sequence.field.value'.tr(), min: 0, max: 255)
      ];
    case DaliCommandType.wait:
      return [CommandMetaField('ms', 'sequence.field.ms'.tr(), min: 1, max: 60000)];
    case DaliCommandType.modifyShortAddress:
      return [
        CommandMetaField('oldAddr', 'sequence.field.oldAddr'.tr(), min: 0, max: 63),
        CommandMetaField('newAddr', 'sequence.field.newAddr'.tr(), min: 0, max: 63),
      ];
    case DaliCommandType.deleteShortAddress:
      return [CommandMetaField('addr', 'sequence.field.addr'.tr(), min: 0, max: 63)];
  }
}
