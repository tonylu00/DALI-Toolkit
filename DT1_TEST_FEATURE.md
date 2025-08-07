# DT1 Emergency Test Feature

## 概述

本功能为DALI Inspector应用添加了DT1应急照明设备的测试功能。该功能包括一个完整的测试对话框界面，可以显示设备信息、测试状态，并提供开始/停止测试的控制。

## 实现的文件

### 1. DT1类增强 (`/lib/dali/dt1.dart`)

**修复的方法:**
- `performDT1Test()`: 添加了正确的延迟实现，使用`Future.delayed()`替代了TODO注释

**新增的方法:**
- `getDT1TestStatusDetailed()`: 提供详细的测试状态信息，包括：
  - 测试进行状态
  - 灯具故障状态
  - 电池故障状态
  - 功能测试状态
  - 持续时间测试状态
  - 测试完成状态

### 2. DT1测试对话框 (`/lib/widgets/common/dt1_test_dialog.dart`)

**主要特性:**
- **设备信息区域**: 显示网关地址、设备地址、设备类型
- **测试状态区域**: 实时显示测试进度和结果
- **动画效果**: 测试进行时显示旋转动画
- **状态颜色**: 不同状态使用不同颜色（灰色-就绪、橙色-进行中、绿色-成功、红色-失败）
- **详细反馈**: 显示具体的故障信息（灯具故障、电池故障等）
- **超时处理**: 30秒测试超时，防止界面卡死

**使用方法:**
```dart
DT1TestDialog.show(
  context,
  gatewayAddress: '192.168.1.100',
  deviceAddress: 1,
  deviceType: 1,
);
```

### 3. DT1测试页面示例 (`/lib/pages/dt1_test_page.dart`)

演示如何使用DT1测试对话框的完整页面，包括：
- 配置参数输入（网关地址、设备地址、设备类型）
- 与当前选中设备的集成
- 启动测试的按钮

### 4. 国际化支持

**中文翻译 (`/assets/translations/zh-CN.json`):**
- DT1应急测试
- 网关地址
- 设备信息
- 测试状态
- 各种测试状态消息

**英文翻译 (`/assets/translations/en.json`):**
- DT1 Emergency Test
- Gateway Address
- Device Information
- Test Status
- Various test status messages

## 界面设计

### 对话框布局
```
┌─────────────────────────────────────┐
│ 🔥 DT1 Emergency Test             │
├─────────────────────────────────────┤
│ 📱 Device Information              │
│   Gateway Address: 192.168.1.100   │
│   Device Address: 1                 │
│   Device Type: DT1 (Emergency Light│
├─────────────────────────────────────┤
│ 📊 Test Status                      │
│   ⟳ Test in progress... (15/30s)   │
└─────────────────────────────────────┘
│ [🛑 Stop Test]     [❌ Close]       │
└─────────────────────────────────────┘
```

### 状态颜色方案
- **就绪**: 灰色 (`Colors.grey`)
- **进行中**: 橙色 (`Colors.orange`)
- **成功**: 绿色 (`Colors.green`)
- **失败/错误**: 红色 (`Colors.red`)

## 测试流程

1. **初始化**: 对话框显示设备信息和就绪状态
2. **启动测试**: 点击"开始测试"按钮
3. **发送命令**: 调用`startDT1Test()`发送测试命令
4. **状态监控**: 每秒轮询测试状态，显示进度
5. **结果处理**: 检测测试完成或故障，显示相应结果
6. **超时处理**: 30秒后自动停止测试

## 错误处理

- **通信错误**: 捕获异常并显示错误信息
- **超时处理**: 防止测试无限期运行
- **用户中断**: 支持用户手动停止测试
- **设备故障**: 详细显示灯具或电池故障信息

## 集成说明

要在现有应用中使用此功能：

1. **导入对话框**:
```dart
import '/widgets/common/dt1_test_dialog.dart';
```

2. **显示对话框**:
```dart
DT1TestDialog.show(
  context,
  gatewayAddress: gatewayAddress,
  deviceAddress: selectedDevice,
  deviceType: 1, // DT1类型
);
```

3. **确保DT1模块可用**:
```dart
// 确保Dali实例已初始化
final dt1 = Dali.instance.dt1;
if (dt1 != null) {
  // 可以使用DT1功能
}
```

## 扩展建议

1. **添加更多设备类型**: 支持DT2、DT3等其他设备类型测试
2. **历史记录**: 保存测试结果历史
3. **批量测试**: 支持多设备同时测试
4. **导出报告**: 生成测试报告文件
5. **自定义超时**: 允许用户设置测试超时时间

## 技术细节

- **状态管理**: 使用StatefulWidget管理测试状态
- **动画**: 使用AnimationController实现旋转动画
- **异步处理**: 正确处理异步测试操作
- **国际化**: 支持中英文切换
- **主题适配**: 自动适配亮色/暗色主题
