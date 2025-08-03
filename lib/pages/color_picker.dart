import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../widgets/custom_color_pickers.dart';

enum ColorPickerMode { wheel, grid, rgb }

class MyColorPicker extends StatefulWidget {
  final ValueChanged<Color> onColorChanged;
  final Color? defaultColor;

  const MyColorPicker({
    super.key,
    required this.onColorChanged,
    this.defaultColor,
  });

  @override
  MyColorState createState() => MyColorState();
}

class MyColorState extends State<MyColorPicker> {
  late Color currentColor;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    currentColor = widget.defaultColor ?? const Color(0xFFFF0000);
  }

  void changeColor(Color color) {
    setState(() => currentColor = color);
    // 确保颜色完全不透明
    final opaqueColor = Color.fromRGBO(color.red, color.green, color.blue, 1.0);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      widget.onColorChanged(opaqueColor);
    });
  }

  void showColorPickerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: _ColorPickerContent(
            initialColor: currentColor,
            onColorChanged: changeColor,
          ),
        );
      },
    );
  }

  Color _getContrastColor(Color color) {
    double luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final foregroundColor = _getContrastColor(currentColor);

    return ElevatedButton.icon(
      onPressed: () => showColorPickerDialog(context),
      icon: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: currentColor,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: foregroundColor.withValues(alpha: 0.3)),
        ),
      ),
      label: Text(
        'Pick color'.tr(),
        style: TextStyle(color: foregroundColor),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: currentColor,
        foregroundColor: foregroundColor,
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

class _ColorPickerContent extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const _ColorPickerContent({
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<_ColorPickerContent> createState() => _ColorPickerContentState();
}

class _ColorPickerContentState extends State<_ColorPickerContent> {
  late ColorPickerMode mode;
  late Color dialogColor;

  @override
  void initState() {
    super.initState();
    mode = ColorPickerMode.wheel;
    dialogColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 800,
        maxHeight: 600,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题和模式切换
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pick a color'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                // 模式切换按钮（窄屏设备）
                if (MediaQuery.of(context).size.width < 600)
                  SegmentedButton<ColorPickerMode>(
                    segments: [
                      ButtonSegment(
                        value: ColorPickerMode.wheel,
                        icon: const Icon(Icons.palette, size: 16),
                        label: Text('Wheel'.tr()),
                      ),
                      ButtonSegment(
                        value: ColorPickerMode.grid,
                        icon: const Icon(Icons.grid_view, size: 16),
                        label: Text('Grid'.tr()),
                      ),
                      ButtonSegment(
                        value: ColorPickerMode.rgb,
                        icon: const Icon(Icons.tune, size: 16),
                        label: Text('RGB'.tr()),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (Set<ColorPickerMode> newSelection) {
                      setState(() {
                        mode = newSelection.first;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 颜色预览
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: dialogColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  'RGB(${dialogColor.red}, ${dialogColor.green}, ${dialogColor.blue})',
                  style: TextStyle(
                    color: _getContrastColor(dialogColor),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 颜色选择器内容
            Flexible(
              child: MediaQuery.of(context).size.width >= 600
                  ? _buildWideScreenLayout(dialogColor, (color) {
                      setState(() {
                        dialogColor = color;
                      });
                    })
                  : _buildNarrowScreenLayout(mode, dialogColor, (color) {
                      setState(() {
                        dialogColor = color;
                      });
                    }),
            ),

            const SizedBox(height: 20),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel'.tr()),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    widget.onColorChanged(dialogColor);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text('OK'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 宽屏布局：同时显示三种选择器
  Widget _buildWideScreenLayout(Color color, ValueChanged<Color> onChanged) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 色彩轮盘
        Expanded(
          child: Column(
            children: [
              Text(
                'Color Wheel'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ColorWheelPicker(
                color: color,
                onColorChanged: onChanged,
                size: 200,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // 色块选择器
        Expanded(
          child: Column(
            children: [
              Text(
                'Color Grid'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                child: ColorGridPicker(
                  color: color,
                  onColorChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // RGB滑块
        Expanded(
          child: Column(
            children: [
              Text(
                'RGB Sliders'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildRGBSliders(color, onChanged),
            ],
          ),
        ),
      ],
    );
  }

  // 窄屏布局：切换显示
  Widget _buildNarrowScreenLayout(
      ColorPickerMode mode, Color color, ValueChanged<Color> onChanged) {
    return SingleChildScrollView(
      child: mode == ColorPickerMode.wheel
          ? ColorWheelPicker(
              color: color,
              onColorChanged: onChanged,
              size: 280,
            )
          : mode == ColorPickerMode.grid
              ? ColorGridPicker(
                  color: color,
                  onColorChanged: onChanged,
                )
              : _buildRGBSliders(color, onChanged),
    );
  }

  // RGB滑块组件
  Widget _buildRGBSliders(Color color, ValueChanged<Color> onChanged) {
    return Column(
      children: [
        _buildRGBSlider('R', color.red, Colors.red, (value) {
          onChanged(Color.fromRGBO(value, color.green, color.blue, 1.0));
        }),
        const SizedBox(height: 16),
        _buildRGBSlider('G', color.green, Colors.green, (value) {
          onChanged(Color.fromRGBO(color.red, value, color.blue, 1.0));
        }),
        const SizedBox(height: 16),
        _buildRGBSlider('B', color.blue, Colors.blue, (value) {
          onChanged(Color.fromRGBO(color.red, color.green, value, 1.0));
        }),
      ],
    );
  }

  Widget _buildRGBSlider(
      String label, int value, Color sliderColor, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: sliderColor,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbColor: sliderColor,
              activeTrackColor: sliderColor.withValues(alpha: 0.8),
              inactiveTrackColor: sliderColor.withValues(alpha: 0.3),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: (val) => onChanged(val.round()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Color _getContrastColor(Color color) {
    double luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
