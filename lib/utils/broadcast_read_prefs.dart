import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 管理是否允许在广播/组地址下执行读取操作的偏好
class BroadcastReadPrefs extends ChangeNotifier {
  BroadcastReadPrefs._();
  static final BroadcastReadPrefs instance = BroadcastReadPrefs._();

  static const _kAllowKey = 'allow_broadcast_read';

  bool _allow = false; // 默认不允许
  bool _loaded = false;

  bool get allow => _allow;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _allow = prefs.getBool(_kAllowKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAllow(bool v) async {
    _allow = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowKey, v);
    notifyListeners();
  }
}
