import 'custom_key.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

const _kCustomKeysStoreKey = 'custom_keys_v1';
const _kCustomKeyGroupsStoreKey = 'custom_key_groups_v1';

class CustomKeyRepository {
  CustomKeyRepository._();
  static final CustomKeyRepository instance = CustomKeyRepository._();

  // ignore: unused_field
  List<CustomKeyDefinition> _keys = [];
  List<CustomKeyGroup> _groups = [];
  List<CustomKeyGroup> get groups =>
      List.unmodifiable(_groups..sort((a, b) => a.order.compareTo(b.order)));
  List<CustomKeyDefinition> get keys => currentGroup?.keys ?? const [];
  CustomKeyGroup? currentGroup;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawGroups = prefs.getString(_kCustomKeyGroupsStoreKey);
    if (rawGroups != null && rawGroups.isNotEmpty) {
      try {
        final list = jsonDecode(rawGroups) as List<dynamic>;
        _groups =
            list.map((e) => CustomKeyGroup.fromJson((e as Map).cast<String, dynamic>())).toList();
      } catch (_) {
        _groups = [];
      }
    } else {
      final rawLegacy = prefs.getString(_kCustomKeysStoreKey);
      if (rawLegacy != null && rawLegacy.isNotEmpty) {
        try {
          final list = jsonDecode(rawLegacy) as List<dynamic>;
          final legacyKeys = list
              .map((e) => CustomKeyDefinition.fromJson((e as Map).cast<String, dynamic>()))
              .toList();
          _groups = [
            CustomKeyGroup(
                id: 'g1', name: 'custom_key.group.default'.tr(), keys: legacyKeys, order: 0)
          ];
          await prefs.remove(_kCustomKeysStoreKey);
          await save();
        } catch (_) {
          _groups = [];
        }
      }
    }
    if (_groups.isEmpty) {
      _groups = [CustomKeyGroup(id: 'g1', name: 'custom_key.group.default'.tr(), order: 0)];
    }
    currentGroup ??= _groups.first;
    _keys = currentGroup!.keys;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _groups.map((e) => e.toJson()).toList();
    await prefs.setString(_kCustomKeyGroupsStoreKey, jsonEncode(list));
  }

  void selectGroup(String id) {
    final g = _groups.firstWhere((e) => e.id == id, orElse: () => _groups.first);
    currentGroup = g;
    _keys = g.keys;
  }

  CustomKeyGroup createGroup(String name) {
    final g = CustomKeyGroup(
        id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, order: _groups.length);
    _groups.add(g);
    currentGroup ??= g;
    return g;
  }

  void renameGroup(CustomKeyGroup g, String name) {
    g.name = name;
  }

  void deleteGroup(CustomKeyGroup g) {
    _groups.removeWhere((e) => e.id == g.id);
    if (_groups.isEmpty) {
      _groups = [CustomKeyGroup(id: 'g1', name: 'custom_key.group.default'.tr(), order: 0)];
    }
    if (currentGroup == null || !_groups.any((e) => e.id == currentGroup!.id)) {
      currentGroup = _groups.first;
    }
    _keys = currentGroup!.keys;
  }

  void add(CustomKeyDefinition k) {
    currentGroup?.keys.add(k);
  }

  void remove(String id) {
    currentGroup?.keys.removeWhere((e) => e.id == id);
  }

  void replace(CustomKeyDefinition k) {
    final list = currentGroup?.keys;
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == k.id);
    if (idx >= 0) {
      list[idx] = k;
    }
  }

  void reorder(int oldIndex, int newIndex) {
    final list = currentGroup?.keys;
    if (list == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    for (int i = 0; i < list.length; i++) {
      list[i].order = i;
    }
  }
}
