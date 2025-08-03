# 颜色选择器使用说明

## 功能概述

颜色选择器现在支持可选的 alpha 通道控制，可以根据使用场景决定是否启用透明度调节。

## 主要特性

### 1. Alpha 通道开关
- `enableAlpha` 参数控制是否启用 alpha 通道
- 默认值为 `false`（禁用 alpha）

### 2. 三种选择器模式
- **色彩轮盘** (Color Wheel): HSV 色彩空间选择
- **色块网格** (Color Grid): 预定义颜色快速选择
- **RGB 滑块** (RGB Sliders): 精确的数值调节

### 3. 响应式布局
- **宽屏** (≥600px): 同时显示三种选择器
- **窄屏** (<600px): 切换式显示，通过分段按钮切换

## 使用方法

### 基本用法

```dart
// 不支持 alpha 的颜色选择器（适用于 Dali 相关功能）
MyColorPicker(
  defaultColor: Colors.red,
  enableAlpha: false, // 禁用 alpha 通道
  onColorChanged: (color) {
    // 颜色始终为完全不透明 (alpha = 255)
    print('RGB: ${color.red}, ${color.green}, ${color.blue}');
  },
)

// 支持 alpha 的颜色选择器（适用于主题颜色）
MyColorPicker(
  defaultColor: Colors.blue.withOpacity(0.8),
  enableAlpha: true, // 启用 alpha 通道
  onColorChanged: (color) {
    // 颜色可以包含透明度信息
    print('RGBA: ${color.red}, ${color.green}, ${color.blue}, ${color.alpha}');
  },
)
```

### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `onColorChanged` | `ValueChanged<Color>` | 必需 | 颜色变化回调 |
| `defaultColor` | `Color?` | `Color(0xFFFF0000)` | 默认颜色 |
| `enableAlpha` | `bool` | `false` | 是否启用 alpha 通道 |

## Alpha 通道行为

### 启用 Alpha (`enableAlpha: true`)
- 显示 RGBA 格式的颜色信息
- 色彩轮盘包含 alpha 滑块
- RGB 滑块包含 alpha 滑块
- 色块选择器保持预定义颜色的原始 alpha 值

### 禁用 Alpha (`enableAlpha: false`)
- 显示 RGB 格式的颜色信息
- 所有颜色输出都强制 alpha = 255（完全不透明）
- 不显示任何 alpha 相关控件
- 色块选择器确保输出颜色完全不透明

## 预定义颜色

色块选择器包含 64 种预定义颜色：
- 8 种色系（红、橙、黄、绿、青、蓝、紫、粉）
- 每种色系 4 种亮度变化
- 每种色系 4 种深度变化
- 8 种灰度颜色

所有预定义颜色的 alpha 通道均为 0xFF（完全不透明）。

## 使用场景

### Dali 相关功能
```dart
MyColorPicker(
  enableAlpha: false,
  // ... 其他参数
)
```
- 颜色始终完全不透明
- 适用于画笔颜色、形状填充等

### 主题颜色选择
```dart
MyColorPicker(
  enableAlpha: true,
  // ... 其他参数
)
```
- 支持透明度调节
- 适用于背景色、叠加效果等

## 技术实现

- `changeColor` 方法根据 `enableAlpha` 参数决定是否保持 alpha 通道
- 所有子组件（ColorWheelPicker、ColorGridPicker）都接收 `enableAlpha` 参数
- RGB 滑块在禁用 alpha 时始终使用 alpha = 1.0
- 色块选择器在禁用 alpha 时强制输出完全不透明的颜色
