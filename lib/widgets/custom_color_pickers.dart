import 'dart:math' as math;
import 'package:flutter/material.dart';

/// HSV颜色类，用于颜色转换
class HSVColor {
  final double hue;
  final double saturation;
  final double value;

  const HSVColor({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  /// 从RGB色彩创建HSV
  factory HSVColor.fromColor(Color color) {
    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;

    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;

    double hue = 0;
    if (delta != 0) {
      if (max == r) {
        hue = ((g - b) / delta) % 6;
      } else if (max == g) {
        hue = (b - r) / delta + 2;
      } else {
        hue = (r - g) / delta + 4;
      }
      hue *= 60;
      if (hue < 0) hue += 360;
    }

    final saturation = max == 0 ? 0.0 : delta / max;
    final value = max;

    return HSVColor(
      hue: hue,
      saturation: saturation,
      value: value,
    );
  }

  /// 转换为RGB颜色
  Color toColor() {
    final c = value * saturation;
    final x = c * (1 - (((hue / 60) % 2) - 1).abs());
    final m = value - c;

    double r = 0, g = 0, b = 0;

    if (hue >= 0 && hue < 60) {
      r = c;
      g = x;
      b = 0;
    } else if (hue >= 60 && hue < 120) {
      r = x;
      g = c;
      b = 0;
    } else if (hue >= 120 && hue < 180) {
      r = 0;
      g = c;
      b = x;
    } else if (hue >= 180 && hue < 240) {
      r = 0;
      g = x;
      b = c;
    } else if (hue >= 240 && hue < 300) {
      r = x;
      g = 0;
      b = c;
    } else if (hue >= 300 && hue < 360) {
      r = c;
      g = 0;
      b = x;
    }

    return Color.fromRGBO(
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
      1.0,
    );
  }

  HSVColor copyWith({
    double? hue,
    double? saturation,
    double? value,
  }) {
    return HSVColor(
      hue: hue ?? this.hue,
      saturation: saturation ?? this.saturation,
      value: value ?? this.value,
    );
  }
}

/// 色彩轮盘选择器
class ColorWheelPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;
  final double size;

  const ColorWheelPicker({
    super.key,
    required this.color,
    required this.onColorChanged,
    this.size = 280,
  });

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late HSVColor currentHSV;

  @override
  void initState() {
    super.initState();
    currentHSV = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(ColorWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color) {
      currentHSV = HSVColor.fromColor(widget.color);
    }
  }

  void _updateColor(HSVColor newHSV) {
    setState(() {
      currentHSV = newHSV;
    });
    widget.onColorChanged(newHSV.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 色彩轮盘
        GestureDetector(
          onPanUpdate: (details) {
            final center = Offset(widget.size / 2, widget.size / 2);
            final offset = details.localPosition - center;
            final distance = offset.distance;
            final radius = widget.size / 2 - 20;

            if (distance <= radius) {
              final angle = math.atan2(offset.dy, offset.dx);
              final hue = (angle * 180 / math.pi + 360) % 360;
              final saturation = (distance / radius).clamp(0.0, 1.0);

              _updateColor(currentHSV.copyWith(
                hue: hue,
                saturation: saturation,
              ));
            }
          },
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: ColorWheelPainter(
              currentHSV: currentHSV,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 明度滑块
        SizedBox(
          width: widget.size * 0.8,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 20,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    currentHSV.copyWith(value: 0).toColor(),
                    currentHSV.copyWith(value: 1).toColor(),
                  ],
                ),
              ),
              child: Slider(
                value: currentHSV.value,
                onChanged: (value) {
                  _updateColor(currentHSV.copyWith(value: value));
                },
                min: 0,
                max: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 色彩轮盘绘制器
class ColorWheelPainter extends CustomPainter {
  final HSVColor currentHSV;

  ColorWheelPainter({required this.currentHSV});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // 绘制色彩环
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 360; i++) {
      final hue = i.toDouble();
      final startAngle = (i - 1) * math.pi / 180;
      final endAngle = (i + 1) * math.pi / 180;

      for (double r = 0; r < radius; r += 2) {
        final saturation = r / radius;
        final color = HSVColor(
          hue: hue,
          saturation: saturation,
          value: currentHSV.value,
        ).toColor();

        paint.color = color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r + 1),
          startAngle,
          endAngle - startAngle,
          true,
          paint,
        );
      }
    }

    // 绘制选择指示器
    final selectedRadius = currentHSV.saturation * radius;
    final selectedAngle = currentHSV.hue * math.pi / 180;
    final selectedPosition = Offset(
      center.dx + selectedRadius * math.cos(selectedAngle),
      center.dy + selectedRadius * math.sin(selectedAngle),
    );

    // 外圈指示器
    canvas.drawCircle(
      selectedPosition,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // 内圈指示器
    canvas.drawCircle(
      selectedPosition,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(ColorWheelPainter oldDelegate) {
    return currentHSV != oldDelegate.currentHSV;
  }
}

/// 色块选择器
class ColorGridPicker extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const ColorGridPicker({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  static const List<Color> _predefinedColors = [
    // 红色系
    Color(0xFFFF0000), Color(0xFFFF4444), Color(0xFFFF8888), Color(0xFFFFCCCC),
    Color(0xFFCC0000), Color(0xFF880000), Color(0xFF440000), Color(0xFF220000),

    // 橙色系
    Color(0xFFFF8800), Color(0xFFFFAA44), Color(0xFFFFCC88), Color(0xFFFFEECC),
    Color(0xFFCC6600), Color(0xFF884400), Color(0xFF442200), Color(0xFF221100),

    // 黄色系
    Color(0xFFFFFF00), Color(0xFFFFFF44), Color(0xFFFFFF88), Color(0xFFFFFFCC),
    Color(0xFFCCCC00), Color(0xFF888800), Color(0xFF444400), Color(0xFF222200),

    // 绿色系
    Color(0xFF00FF00), Color(0xFF44FF44), Color(0xFF88FF88), Color(0xFFCCFFCC),
    Color(0xFF00CC00), Color(0xFF008800), Color(0xFF004400), Color(0xFF002200),

    // 青色系
    Color(0xFF00FFFF), Color(0xFF44FFFF), Color(0xFF88FFFF), Color(0xFFCCFFFF),
    Color(0xFF00CCCC), Color(0xFF008888), Color(0xFF004444), Color(0xFF002222),

    // 蓝色系
    Color(0xFF0000FF), Color(0xFF4444FF), Color(0xFF8888FF), Color(0xFFCCCCFF),
    Color(0xFF0000CC), Color(0xFF000088), Color(0xFF000044), Color(0xFF000022),

    // 紫色系
    Color(0xFF8800FF), Color(0xFFAA44FF), Color(0xFFCC88FF), Color(0xFFEECCFF),
    Color(0xFF6600CC), Color(0xFF440088), Color(0xFF220044), Color(0xFF110022),

    // 粉色系
    Color(0xFFFF00FF), Color(0xFFFF44FF), Color(0xFFFF88FF), Color(0xFFFFCCFF),
    Color(0xFFCC00CC), Color(0xFF880088), Color(0xFF440044), Color(0xFF220022),

    // 灰色系
    Color(0xFF000000), Color(0xFF333333), Color(0xFF666666), Color(0xFF999999),
    Color(0xFFCCCCCC), Color(0xFFDDDDDD), Color(0xFFEEEEEE), Color(0xFFFFFFFF),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 预定义颜色网格
        Container(
          width: 320,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: _predefinedColors.length,
            itemBuilder: (context, index) {
              final colorItem = _predefinedColors[index];
              final isSelected = _colorsAreEqual(color, colorItem);

              return GestureDetector(
                onTap: () => onColorChanged(colorItem),
                child: Container(
                  decoration: BoxDecoration(
                    color: colorItem,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.grey.shade400,
                      width: isSelected ? 3 : 1,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: _getContrastColor(colorItem),
                          size: 16,
                        )
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // RGB滑块
        _buildRGBSliders(),
      ],
    );
  }

  Widget _buildRGBSliders() {
    return Column(
      children: [
        _buildRGBSlider('R', color.red, Colors.red, (value) {
          onColorChanged(Color.fromRGBO(value, color.green, color.blue, 1.0));
        }),
        const SizedBox(height: 8),
        _buildRGBSlider('G', color.green, Colors.green, (value) {
          onColorChanged(Color.fromRGBO(color.red, value, color.blue, 1.0));
        }),
        const SizedBox(height: 8),
        _buildRGBSlider('B', color.blue, Colors.blue, (value) {
          onColorChanged(Color.fromRGBO(color.red, color.green, value, 1.0));
        }),
      ],
    );
  }

  Widget _buildRGBSlider(
      String label, int value, Color sliderColor, ValueChanged<int> onChanged) {
    return Builder(
      builder: (context) => Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: sliderColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbColor: sliderColor,
                activeTrackColor: sliderColor.withValues(alpha: 0.8),
                inactiveTrackColor: sliderColor.withValues(alpha: 0.3),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
          const SizedBox(width: 8),
          SizedBox(
            width: 35,
            child: Text(
              value.toString(),
              style: const TextStyle(fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  bool _colorsAreEqual(Color a, Color b) {
    return a.red == b.red && a.green == b.green && a.blue == b.blue;
  }

  Color _getContrastColor(Color color) {
    double luminance =
        (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
