# Widgets 目录结构

本目录包含所有的自定义 Widget 组件，按功能分类组织：

## 目录结构

```
widgets/
├── widgets.dart              # 统一导出文件，用于简化导入
├── common/                   # 通用组件
│   ├── device_status_widget.dart
│   ├── toast_test_buttons_widget.dart
│   └── optimized_widgets.dart
├── controls/                 # 控制相关组件
│   ├── brightness_control_widget.dart
│   ├── color_temperature_control_widget.dart
│   ├── device_control_buttons_widget.dart
│   ├── group_control_widget.dart
│   └── read_operation_buttons_widget.dart
├── color/                    # 颜色相关组件
│   ├── color_control_widget.dart
│   └── custom_color_pickers.dart
└── settings/                 # 设置相关组件
    ├── addressing_settings.dart
    ├── connection_method_setting.dart
    ├── dark_mode_setting.dart
    ├── delays_setting.dart
    ├── dimming_curve_setting.dart
    ├── language_setting.dart
    ├── settings_card.dart
    ├── settings_item.dart
    ├── settings_option_button.dart
    └── theme_color_setting.dart
```

## 使用方法

### 方式一：统一导入（推荐）
```dart
import '../widgets/widgets.dart'; // 导入所有组件
```

### 方式二：按需导入
```dart
// 导入特定类别的组件
import '../widgets/controls/brightness_control_widget.dart';
import '../widgets/settings/theme_color_setting.dart';
import '../widgets/color/custom_color_pickers.dart';
```

## 组件分类说明

### Common（通用组件）
- **device_status_widget.dart**: 设备状态显示组件
- **toast_test_buttons_widget.dart**: Toast 测试按钮组件
- **optimized_widgets.dart**: 优化的通用组件

### Controls（控制组件）
- **brightness_control_widget.dart**: 亮度控制组件
- **color_temperature_control_widget.dart**: 色温控制组件
- **device_control_buttons_widget.dart**: 设备控制按钮组件
- **group_control_widget.dart**: 组控制组件
- **read_operation_buttons_widget.dart**: 读取操作按钮组件

### Color（颜色组件）
- **color_control_widget.dart**: 颜色控制组件
- **custom_color_pickers.dart**: 自定义颜色选择器

### Settings（设置组件）
- **addressing_settings.dart**: 地址设置组件
- **connection_method_setting.dart**: 连接方法设置
- **dark_mode_setting.dart**: 深色模式设置
- **delays_setting.dart**: 延迟设置
- **dimming_curve_setting.dart**: 调光曲线设置
- **language_setting.dart**: 语言设置
- **settings_card.dart**: 设置卡片组件
- **settings_item.dart**: 设置项组件
- **settings_option_button.dart**: 设置选项按钮
- **theme_color_setting.dart**: 主题颜色设置

## 重构优势

### 1. 代码组织
- **清晰的分类**: 按功能领域分组，便于查找和维护
- **统一导入**: 通过 `widgets.dart` 简化导入语句
- **模块化**: 每个组件都有明确的职责边界

### 2. 性能优化
- **减少重建**: 独立组件只在自身状态变化时重建
- **更好的内存管理**: 组件级别的生命周期管理
- **优化的 Widget 树**: 减少不必要的嵌套

### 3. 可维护性
- **单一职责**: 每个组件专注于特定功能
- **松耦合**: 通过回调函数进行组件间通信
- **易于测试**: 独立组件便于单元测试

### 4. 可扩展性
- **易于添加新组件**: 只需放入相应分类目录
- **支持主题系统**: 基于 Material Design 3
- **国际化准备**: 支持多语言文本

## 注意事项

1. **新增组件时**，请将其放入合适的分类目录中
2. **添加导出**，在 `widgets.dart` 中添加相应的导出语句
3. **使用统一导入**，推荐使用 `import '../widgets/widgets.dart'`
4. **遵循命名规范**，使用描述性的文件名和类名
5. **更新文档**，添加新组件时请更新此 README

## 后续改进方向

1. **动画增强**: 为组件状态变化添加流畅过渡
2. **主题支持**: 完善亮色/暗色主题切换
3. **性能监控**: 添加组件性能分析工具
4. **自动化测试**: 建立组件单元测试框架
5. **文档生成**: 自动生成 API 文档
