import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../widgets/widgets.dart';

enum ColorPickerMode { wheel, grid, rgb }

class MyColorPicker extends StatefulWidget {
  final ValueChanged<Color> onColorChanged;
  final Color? defaultColor;
  final bool enableAlpha;

  const MyColorPicker({
    super.key,
    required this.onColorChanged,
    this.defaultColor,
    this.enableAlpha = false,
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
    // 根据enableAlpha决定是否保持alpha通道
    final finalColor = widget.enableAlpha
        ? color
        : Color.fromRGBO((color.r * 255.0).round(), (color.g * 255.0).round(),
            (color.b * 255.0).round(), 1.0);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      widget.onColorChanged(finalColor);
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
            enableAlpha: widget.enableAlpha,
          ),
        );
      },
    );
  }

  Color _getContrastColor(Color color) {
    double luminance = (0.299 * color.r * 255.0 +
            0.587 * color.g * 255.0 +
            0.114 * color.b * 255.0) /
        255;
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
  final bool enableAlpha;

  const _ColorPickerContent({
    required this.initialColor,
    required this.onColorChanged,
    required this.enableAlpha,
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
                  widget.enableAlpha
                      ? 'RGBA(${(dialogColor.r * 255.0).round()}, ${(dialogColor.g * 255.0).round()}, ${(dialogColor.b * 255.0).round()}, ${(dialogColor.a * 100).round()}%)'
                      : 'RGB(${(dialogColor.r * 255.0).round()}, ${(dialogColor.g * 255.0).round()}, ${(dialogColor.b * 255.0).round()})',
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
                enableAlpha: widget.enableAlpha,
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
                  enableAlpha: widget.enableAlpha,
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
              enableAlpha: widget.enableAlpha,
            )
          : mode == ColorPickerMode.grid
              ? ColorGridPicker(
                  color: color,
                  onColorChanged: onChanged,
                  enableAlpha: widget.enableAlpha,
                )
              : _buildRGBSliders(color, onChanged),
    );
  }

  // RGB滑块组件
  Widget _buildRGBSliders(Color color, ValueChanged<Color> onChanged) {
    final alpha = widget.enableAlpha ? color.a : 1.0;

    return Column(
      children: [
        _buildRGBSlider('R', (color.r * 255.0).round(), Colors.red, (value) {
          onChanged(Color.fromRGBO(value, (color.g * 255.0).round(),
              (color.b * 255.0).round(), alpha));
        }),
        const SizedBox(height: 16),
        _buildRGBSlider('G', (color.g * 255.0).round(), Colors.green, (value) {
          onChanged(Color.fromRGBO((color.r * 255.0).round(), value,
              (color.b * 255.0).round(), alpha));
        }),
        const SizedBox(height: 16),
        _buildRGBSlider('B', (color.b * 255.0).round(), Colors.blue, (value) {
          onChanged(Color.fromRGBO((color.r * 255.0).round(),
              (color.g * 255.0).round(), value, alpha));
        }),
        if (widget.enableAlpha) ...[
          const SizedBox(height: 16),
          _buildAlphaSlider((color.a * 255.0).round(), (value) {
            onChanged(Color.fromRGBO(
                (color.r * 255.0).round(),
                (color.g * 255.0).round(),
                (color.b * 255.0).round(),
                value / 255.0));
          }),
        ],
      ],
    );
  }

  Widget _buildAlphaSlider(int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            'A',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbColor: Colors.grey[700],
              activeTrackColor: Colors.grey[700]!.withValues(alpha: 0.8),
              inactiveTrackColor: Colors.grey[300],
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [Colors.transparent, Colors.black],
                ),
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
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            '${(value / 255 * 100).round()}%',
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
    double luminance = (0.299 * color.r * 255.0 +
            0.587 * color.g * 255.0 +
            0.114 * color.b * 255.0) /
        255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
