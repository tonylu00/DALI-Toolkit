import 'dart:async';
import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '../toast.dart';
import '/connection/manager.dart';
import '../utils/colour_track_shape.dart';
import 'package:easy_localization/easy_localization.dart';

class ColorTemperatureControlWidget extends StatefulWidget {
  final double colorTemperature;
  final ValueChanged<double> onColorTemperatureChanged;

  const ColorTemperatureControlWidget({
    super.key,
    required this.colorTemperature,
    required this.onColorTemperatureChanged,
  });

  @override
  State<ColorTemperatureControlWidget> createState() =>
      _ColorTemperatureControlWidgetState();
}

class _ColorTemperatureControlWidgetState
    extends State<ColorTemperatureControlWidget> {
  Timer? _debounce;

  bool _checkDeviceConnection() {
    final connection = ConnectionManager.instance.connection;
    if (connection.isDeviceConnected() == false) {
      ToastManager().showErrorToast('Device not connected');
      return false;
    }
    return true;
  }

  Future<void> _readColorTemperature() async {
    if (!_checkDeviceConnection()) return;

    int colorTemp = await Dali.instance.dt8!
        .getColorTemperature(Dali.instance.base!.selectedAddress);
    if (colorTemp < 2700) {
      colorTemp = 2700;
    }
    if (colorTemp > 6500) {
      colorTemp = 6500;
    }
    widget.onColorTemperatureChanged(colorTemp.toDouble());
  }

  void _setColorTemperature(double value) {
    if (!_checkDeviceConnection()) return;

    widget.onColorTemperatureChanged(value);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 50), () {
      Dali.instance.dt8!.setColorTemperature(
          Dali.instance.base!.selectedAddress, value.toInt());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
            color: Theme.of(context).shadowColor.withOpacity(0.1),
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
                    Icons.thermostat,
                    color: Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Color Temperature'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.colorTemperature.toInt()}K',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _readColorTemperature,
                    icon: Icon(
                      Icons.refresh,
                      color: Colors.orange,
                    ),
                    tooltip: 'Read'.tr(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8.0,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                trackShape: GradientTrackShape(colors: [
                  Colors.yellow.shade300,
                  Colors.white,
                  Colors.lightBlue.shade300
                ]),
                thumbColor: Colors.orange,
                overlayColor: Colors.orange.withAlpha(32),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 14.0),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 20.0),
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                valueIndicatorColor: Colors.orange,
                valueIndicatorTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Slider(
                value: widget.colorTemperature,
                min: 2700,
                max: 6500,
                divisions: 3800,
                label: '${widget.colorTemperature.toInt()}K',
                onChanged: _setColorTemperature,
              ),
            ),
          ),
          // 预设色温快捷按钮
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetButton(context, 'Warm', 2700, Colors.yellow.shade600),
              _buildPresetButton(context, 'Soft', 3500, Colors.orange.shade300),
              _buildPresetButton(context, 'Natural', 4500, Colors.white),
              _buildPresetButton(context, 'Cool', 5500, Colors.blue.shade200),
              _buildPresetButton(
                  context, 'Daylight', 6500, Colors.lightBlue.shade300),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(
      BuildContext context, String label, double value, Color indicatorColor) {
    final isSelected = (widget.colorTemperature - value).abs() < 50;

    return GestureDetector(
      onTap: () => _setColorTemperature(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.orange.withOpacity(0.15)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.orange
                : Theme.of(context).colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 4,
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.grey.shade400, width: 0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? Colors.orange.shade700
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
