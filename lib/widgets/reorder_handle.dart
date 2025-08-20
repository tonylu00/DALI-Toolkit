import 'package:flutter/material.dart';

/// 统一的拖拽手柄样式
/// 使用时配合 ReorderableDragStartListener 包裹
class ReorderHandle extends StatelessWidget {
  final EdgeInsets padding;
  final Color? color;
  const ReorderHandle(
      {super.key,
      this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      this.color});
  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).iconTheme.color;
    return Padding(
      padding: padding,
      child: Icon(Icons.drag_handle, size: 20, color: iconColor),
    );
  }
}
