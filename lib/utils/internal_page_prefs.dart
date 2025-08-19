import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 管理内部页面记忆设置与最近一次页面记录
class InternalPagePrefs extends ChangeNotifier {
  static final InternalPagePrefs instance = InternalPagePrefs._();
  InternalPagePrefs._();

  static const _kRememberKey = 'remember_internal_page';
  static const _kLastPageKey = 'last_internal_page';

  bool _remember = false; // 默认关闭
  String? _lastPage;
  bool _loaded = false;

  bool get remember => _remember;
  String? get lastPage => _lastPage;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _remember = prefs.getBool(_kRememberKey) ?? false;
    _lastPage = prefs.getString(_kLastPageKey);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRemember(bool value) async {
    _remember = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberKey, value);
    if (!value) {
      // 关闭记忆可选择是否清除最后页面: 这里保留但不再使用
    }
    notifyListeners();
  }

  Future<void> setLastPage(String key) async {
    _lastPage = key;
    if (!_remember) return; // 未开启不写入
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastPageKey, key);
  }
}
