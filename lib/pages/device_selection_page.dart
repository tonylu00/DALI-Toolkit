import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../dali/addr.dart';
import '../widgets/panels/device_selection_panel.dart';

/// 设备选择页面（原弹窗重构）
///
/// 特性：
/// - 与原对话框逻辑一致：扫描/停止、广播模式切换、范围输入、列表选择
/// - 页面形式便于横屏常驻；可直接放入 SplitView / NavigationRail 布局
/// - 响应式：宽屏时左右布局，窄屏上下布局
class DeviceSelectionPage extends StatelessWidget {
  final DaliAddr daliAddr;
  const DeviceSelectionPage({super.key, required this.daliAddr});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Online Devices').tr()),
      body: DeviceSelectionPanel(daliAddr: daliAddr),
    );
  }
}
