import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';

/// 自定义按键动作类型
/// 可扩展: 运行指令序列、执行地址分配、分配并重置、发送单条基础命令等
/// 先实现核心需求: 运行序列 + 地址分配相关
enum CustomKeyActionType {
  runSequence, // 运行某个指令序列
  allocateAddresses, // 执行快速地址分配 (allocateAllAddr)
  resetAndAllocate, // 执行 resetAndAllocAddr
  on, // 开
  off, // 关
  setBright, // 设置亮度
  toScene, // 跳转场景
  setScene, // 设置场景
  addToGroup, // 加入分组
  removeFromGroup, // 移出分组
  toggleOnOff, // 新增: 切换开关
}

extension CustomKeyActionTypeI18n on CustomKeyActionType {
  String i18nKey() => 'custom_key.action.$name';
  String label() => i18nKey().tr();
}

class CustomKeyParams {
  final Map<String, dynamic> data;
  CustomKeyParams([Map<String, dynamic>? d]) : data = d ?? {};
  T? get<T>(String k) => data[k] as T?;
  int getInt(String k, [int def = 0]) => (data[k] as int?) ?? def;
  Map<String, dynamic> toJson() => data;
  factory CustomKeyParams.fromJson(Map<String, dynamic> json) =>
      CustomKeyParams(json);
}

class CustomKeyDefinition {
  String id; // 唯一 ID
  String name; // 按键显示名称
  CustomKeyActionType actionType;
  CustomKeyParams params;
  int order; // 排序序号
  CustomKeyDefinition({
    required this.id,
    required this.name,
    required this.actionType,
    CustomKeyParams? params,
    required this.order,
  }) : params = params ?? CustomKeyParams();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'actionType': actionType.name,
        'params': params.toJson(),
        'order': order,
      };
  factory CustomKeyDefinition.fromJson(Map<String, dynamic> json) =>
      CustomKeyDefinition(
        id: json['id'],
        name: json['name'],
        actionType: CustomKeyActionType.values.firstWhere(
            (e) => e.name == json['actionType'],
            orElse: () => CustomKeyActionType.runSequence),
        params: CustomKeyParams.fromJson(
            (json['params'] as Map?)?.cast<String, dynamic>() ?? {}),
        order: (json['order'] as int?) ?? 0,
      );
}

/// 每个自定义按键动作需要的参数元数据
class CustomKeyActionFieldMeta {
  final String key;
  final String labelKey; // i18n key
  final int? min;
  final int? max;
  const CustomKeyActionFieldMeta(this.key, this.labelKey, {this.min, this.max});
}

List<CustomKeyActionFieldMeta> customKeyActionMeta(CustomKeyActionType t) {
  switch (t) {
    case CustomKeyActionType.runSequence:
    case CustomKeyActionType.allocateAddresses:
    case CustomKeyActionType.resetAndAllocate:
      return [];
    case CustomKeyActionType.on:
    case CustomKeyActionType.off:
      return [
        CustomKeyActionFieldMeta('addr', 'sequence.field.addr',
            min: 0, max: 127)
      ];
    case CustomKeyActionType.setBright:
      return [
        CustomKeyActionFieldMeta('addr', 'sequence.field.addr',
            min: 0, max: 127),
        CustomKeyActionFieldMeta('level', 'sequence.field.level',
            min: 0, max: 254),
      ];
    case CustomKeyActionType.toScene:
    case CustomKeyActionType.setScene:
      return [
        CustomKeyActionFieldMeta('addr', 'sequence.field.addr',
            min: 0, max: 127),
        CustomKeyActionFieldMeta('scene', 'sequence.field.scene',
            min: 0, max: 15),
      ];
    case CustomKeyActionType.addToGroup:
    case CustomKeyActionType.removeFromGroup:
      return [
        CustomKeyActionFieldMeta('addr', 'sequence.field.addr',
            min: 0, max: 127),
        CustomKeyActionFieldMeta('group', 'sequence.field.group',
            min: 0, max: 15),
      ];
    case CustomKeyActionType.toggleOnOff:
      return [
        CustomKeyActionFieldMeta('addr', 'sequence.field.addr',
            min: 0, max: 127)
      ];
  }
}

/// 简单的序列化/反序列化工具 (调试/导入导出可用)
String encodeCustomKeys(List<CustomKeyDefinition> list) =>
    jsonEncode(list.map((e) => e.toJson()).toList());
List<CustomKeyDefinition> decodeCustomKeys(String raw) {
  final data = jsonDecode(raw);
  if (data is! List) return [];
  return data
      .map((e) =>
          CustomKeyDefinition.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}

class CustomKeyGroup {
  String id;
  String name;
  List<CustomKeyDefinition> keys;
  int order;
  CustomKeyGroup(
      {required this.id,
      required this.name,
      List<CustomKeyDefinition>? keys,
      required this.order})
      : keys = keys ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'order': order,
        'keys': keys.map((e) => e.toJson()).toList(),
      };
  factory CustomKeyGroup.fromJson(Map<String, dynamic> json) => CustomKeyGroup(
        id: json['id'],
        name: json['name'] ?? '',
        order: (json['order'] as int?) ?? 0,
        keys: (json['keys'] as List? ?? [])
            .map((e) => CustomKeyDefinition.fromJson(
                (e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
