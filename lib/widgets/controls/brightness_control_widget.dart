import 'dart:async';
import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '/toast.dart';
import '/connection/manager.dart';
import '/utils/colour_track_shape.dart';
import 'package:easy_localization/easy_localization.dart';

class BrightnessControlWidget extends StatefulWidget {
  final double brightness;
  final ValueChanged<double> onBrightnessChanged;

  const BrightnessControlWidget({
    super.key,
    required this.brightness,
    required this.onBrightnessChanged,
  });

  @override
  State<BrightnessControlWidget> createState() =>
      _BrightnessControlWidgetState();
}

class _BrightnessControlWidgetState extends State<BrightnessControlWidget> {
  Timer? _debounce;

  bool _checkDeviceConnection() {
    final connection = ConnectionManager.instance.connection;
    if (connection.isDeviceConnected() == false) {
      ToastManager().showErrorToast('Device not connected');
      return false;
    }
    return true;
  }

  Future<void> _readBrightness() async {
    if (!_checkDeviceConnection()) return;

    final bright = await Dali.instance.base!
        .getBright(Dali.instance.base!.selectedAddress);
    if (bright == null || bright < 0 || bright > 254) {
      return;
    }
    widget.onBrightnessChanged(bright.toDouble());
  }

  void _setBrightness(double value) {
    if (!_checkDeviceConnection()) return;

    widget.onBrightnessChanged(value);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 50), () {
      Dali.instance.base!
          .setBright(Dali.instance.base!.selectedAddress, value.toInt());
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
                    Icons.brightness_6,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Brightness'.tr(),
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
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.brightness.toInt()}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _readBrightness,
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
                trackShape:
                    GradientTrackShape(colors: [Colors.black, Colors.white]),
                thumbColor: Theme.of(context).colorScheme.primary,
                overlayColor:
                    Theme.of(context).colorScheme.primary.withAlpha(32),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 14.0),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 20.0),
                valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
                valueIndicatorColor: Theme.of(context).colorScheme.primary,
                valueIndicatorTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Slider(
                value: widget.brightness,
                min: 0,
                max: 254,
                divisions: 255,
                label: widget.brightness.toInt().toString(),
                onChanged: _setBrightness,
              ),
            ),
          ),
          // 预设值快捷按钮
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPresetButton(context, '0%', 0),
              _buildPresetButton(context, '25%', 63),
              _buildPresetButton(context, '50%', 127),
              _buildPresetButton(context, '75%', 191),
              _buildPresetButton(context, '100%', 254),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(BuildContext context, String label, double value) {
    final isSelected = (widget.brightness - value).abs() < 2;

    return GestureDetector(
      onTap: () => _setBrightness(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ),
    );
  }
}
