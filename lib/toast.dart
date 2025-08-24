import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'main.dart';

/// Toast 类型枚举，统一管理样式与语义
enum ToastType { loading, done, error, warning, info, normal }

class ToastManager {
  static final ToastManager _instance = ToastManager._internal();
  factory ToastManager() => _instance;

  ToastManager._internal();

  late FToast _fToast;
  bool _initialized = false;

  // 去重判定字段
  String? _lastMessage;
  ToastType? _lastType;
  DateTime? _lastShownAt;

  // 配置：相同内容最小重复间隔
  Duration minDuplicateInterval = const Duration(milliseconds: 1500);

  void init() {
    if (_initialized) return;
    _fToast = FToast();
    // 依赖 navigatorKey 提供的 context
    if (navigatorKey.currentContext != null) {
      _fToast.init(navigatorKey.currentContext!);
      _initialized = true;
    }
  }

  void _ensureInit() {
    if (!_initialized) {
      init();
    }
  }

  /// 通用展示接口。
  /// force = true 可忽略去重限制；clearPrevious = true 会移除之前的 toast。
  bool show(
    String message, {
    ToastType type = ToastType.normal,
    Duration? duration,
    bool force = false,
    bool clearPrevious = false,
  }) {
    _ensureInit();
    if (!_initialized) return false; // 仍未初始化，直接放弃

    final now = DateTime.now();
    final effectiveDuration = duration ?? const Duration(seconds: 2);

    if (!force && _isDuplicate(message, type, now)) {
      return false; // 忽略重复
    }

    if (clearPrevious) {
      _fToast.removeQueuedCustomToasts();
    }

    final theme = Theme.of(navigatorKey.currentContext!);
    final scheme = theme.colorScheme;

    // 根据类型映射样式
    Color bgColor;
    Color fgColor;
    IconData? iconData;
    bool showProgress = false;

    switch (type) {
      case ToastType.loading:
        bgColor = scheme.secondary;
        fgColor = scheme.onSecondary;
        showProgress = true;
        break;
      case ToastType.done:
        bgColor = scheme.secondary;
        fgColor = scheme.onSecondary;
        iconData = Icons.check;
        break;
      case ToastType.error:
        bgColor = scheme.error;
        fgColor = scheme.onError;
        iconData = Icons.error;
        break;
      case ToastType.warning:
        bgColor = scheme.tertiary;
        fgColor = scheme.onTertiary;
        iconData = Icons.warning;
        break;
      case ToastType.info:
        bgColor = scheme.primary;
        fgColor = scheme.onPrimary;
        iconData = Icons.info;
        break;
      case ToastType.normal:
        bgColor = scheme.secondary;
        fgColor = scheme.onSecondary;
        break;
    }

    final Widget toast = _buildToast(
      message: message,
      bgColor: bgColor,
      fgColor: fgColor,
      iconData: iconData,
      showProgress: showProgress,
    );

    _fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: effectiveDuration,
    );

    _lastMessage = message;
    _lastType = type;
    _lastShownAt = now;
    return true;
  }

  bool _isDuplicate(String message, ToastType type, DateTime now) {
    if (_lastMessage == null || _lastType == null || _lastShownAt == null) {
      return false;
    }
    if (_lastMessage != message || _lastType != type) return false;
    return now.difference(_lastShownAt!) < minDuplicateInterval;
  }

  Widget _buildToast({
    required String message,
    required Color bgColor,
    required Color fgColor,
    IconData? iconData,
    bool showProgress = false,
  }) {
    final children = <Widget>[];
    if (showProgress) {
      children.add(SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(fgColor),
        ),
      ));
    } else if (iconData != null) {
      children.add(Icon(iconData, color: fgColor));
    }
    if (children.isNotEmpty) {
      children.add(const SizedBox(width: 12));
    }
    children.add(
      Flexible(
        child: Text(
          message,
          style: TextStyle(color: fgColor),
          overflow: TextOverflow.fade,
          softWrap: true,
        ).tr(),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: bgColor,
        boxShadow: [
          BoxShadow(
            // 使用 withValues 替代已弃用的 withOpacity
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  // ---------------- 兼容旧 API ----------------
  void showLoadingToast(String message) => show(message, type: ToastType.loading, force: true);
  void showDoneToast(String message) => show(message, type: ToastType.done);
  void showErrorToast(String message) => show(message, type: ToastType.error);
  void showWarningToast(String message) => show(message, type: ToastType.warning);
  void showInfoToast(String message) => show(message, type: ToastType.info);
  void showToast(String message) => show(message, type: ToastType.normal);
}
