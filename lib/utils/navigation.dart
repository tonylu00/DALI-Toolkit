import 'package:flutter/material.dart';

/// 全局路由导航工具，避免重复创建页面实例。
/// 使用规则：不适用于需要等待返回值 (then) 的场景。
void navigateToPage(BuildContext context, String routeName) {
  final current = ModalRoute.of(context)?.settings.name;
  if (current == routeName) return;
  bool found = false;
  Navigator.popUntil(context, (route) {
    if (route.settings.name == routeName) {
      found = true;
      return true; // 停在已存在的目标路由
    }
    return route.isFirst; // 继续直到根路由
  });
  if (!found) {
    Navigator.restorablePushNamed(context, routeName);
  }
}
