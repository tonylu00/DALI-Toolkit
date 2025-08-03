import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../pages/color_picker.dart';

class ColorPickerTestPage extends StatefulWidget {
  const ColorPickerTestPage({super.key});

  @override
  State<ColorPickerTestPage> createState() => _ColorPickerTestPageState();
}

class _ColorPickerTestPageState extends State<ColorPickerTestPage> {
  Color themeColor = Colors.blue; // 主题颜色，支持alpha
  Color daliColor = Colors.red; // Dali相关颜色，不支持alpha

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Color Picker Test'.tr()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 主题颜色选择器（启用alpha）
            Text(
              'Theme Color (Alpha Enabled)'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            MyColorPicker(
              defaultColor: themeColor,
              enableAlpha: true, // 启用alpha通道
              onColorChanged: (color) {
                setState(() {
                  themeColor = color;
                });
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: Center(
                child: Text(
                  'RGBA(${(themeColor.r * 255.0).round()}, ${(themeColor.g * 255.0).round()}, ${(themeColor.b * 255.0).round()}, ${(themeColor.a * 100).round()}%)',
                  style: TextStyle(
                    color: _getContrastColor(themeColor),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Dali颜色选择器（禁用alpha）
            Text(
              'Dali Color (Alpha Disabled)'.tr(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            MyColorPicker(
              defaultColor: daliColor,
              enableAlpha: false, // 禁用alpha通道
              onColorChanged: (color) {
                setState(() {
                  daliColor = color;
                });
              },
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                color: daliColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: Center(
                child: Text(
                  'RGB(${(daliColor.r * 255.0).round()}, ${(daliColor.g * 255.0).round()}, ${(daliColor.b * 255.0).round()})',
                  style: TextStyle(
                    color: _getContrastColor(daliColor),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
