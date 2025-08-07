import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '/dali/color.dart';
import '/toast.dart';
import '/connection/manager.dart';
import '/pages/color_picker.dart';
import 'package:easy_localization/easy_localization.dart';

class ColorControlWidget extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const ColorControlWidget({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  @override
  State<ColorControlWidget> createState() => _ColorControlWidgetState();
}

class _ColorControlWidgetState extends State<ColorControlWidget> {
  bool _checkDeviceConnection() {
    final connection = ConnectionManager.instance.connection;
    if (connection.isDeviceConnected() == false) {
      ToastManager().showErrorToast('Device not connected');
      return false;
    }
    return true;
  }

  Future<void> _readColor() async {
    if (!_checkDeviceConnection()) return;

    final colorRGB = await Dali.instance.dt8!
        .getColourRGB(Dali.instance.base!.selectedAddress);
    if (colorRGB.isEmpty) {
      return;
    }
    debugPrint('Color: $colorRGB');
    final colorObj = Color(
        (0xFF << 24) + (colorRGB[0] << 16) + (colorRGB[1] << 8) + colorRGB[2]);
    widget.onColorChanged(colorObj);
  }

  Future<void> _setColor(Color colorNew) async {
    final colorRGB = DaliColor.toIntList(colorNew);
    widget.onColorChanged(colorNew);
    if (!_checkDeviceConnection()) return;
    Dali.instance.dt8!.setColourRGB(Dali.instance.base!.selectedAddress,
        colorRGB[1], colorRGB[2], colorRGB[3]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.palette,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Color'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              IconButton(
                onPressed: _readColor,
                icon: Icon(
                  Icons.refresh,
                  color: Theme.of(context).colorScheme.primary,
                ),
                tooltip: 'Read'.tr(),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // 颜色预览
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // RGB 值显示
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRGBValue(
                        'R', (widget.color.r * 255).toInt(), Colors.red),
                    const SizedBox(height: 4),
                    _buildRGBValue(
                        'G', (widget.color.g * 255).toInt(), Colors.green),
                    const SizedBox(height: 4),
                    _buildRGBValue(
                        'B', (widget.color.b * 255).toInt(), Colors.blue),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 颜色选择器
              MyColorPicker(
                onColorChanged: _setColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 预设颜色快捷按钮
          Text(
            'Presets'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildColorPreset(Colors.red, 'Red'),
              _buildColorPreset(Colors.green, 'Green'),
              _buildColorPreset(Colors.blue, 'Blue'),
              _buildColorPreset(Colors.yellow, 'Yellow'),
              _buildColorPreset(Colors.purple, 'Purple'),
              _buildColorPreset(Colors.orange, 'Orange'),
              _buildColorPreset(Colors.cyan, 'Cyan'),
              _buildColorPreset(Colors.pink, 'Pink'),
              _buildColorPreset(Colors.white, 'White'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRGBValue(String label, int value, Color color) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value.toString().padLeft(3, '0'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildColorPreset(Color color, String name) {
    final isSelected = _colorsAreEqual(widget.color, color);

    return GestureDetector(
      onTap: () => _setColor(color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: _getContrastColor(color),
                size: 16,
              )
            : null,
      ),
    );
  }

  bool _colorsAreEqual(Color a, Color b) {
    return ((a.r * 255.0).round() - (b.r * 255.0).round()).abs() < 10 &&
        ((a.g * 255.0).round() - (b.g * 255.0).round()).abs() < 10 &&
        ((a.b * 255.0).round() - (b.b * 255.0).round()).abs() < 10;
  }

  Color _getContrastColor(Color color) {
    // Calculate relative luminance
    double luminance = (0.299 * color.r * 255.0 +
            0.587 * color.g * 255.0 +
            0.114 * color.b * 255.0) /
        255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
