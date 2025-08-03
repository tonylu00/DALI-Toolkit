import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ReadOperationButtonsWidget extends StatelessWidget {
  final VoidCallback onReadBrightness;
  final VoidCallback onReadColorTemperature;
  final VoidCallback onReadColor;

  const ReadOperationButtonsWidget({
    super.key,
    required this.onReadBrightness,
    required this.onReadColorTemperature,
    required this.onReadColor,
  });

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
            children: [
              Icon(
                Icons.download,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Read Operations'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildReadButton(
                  context,
                  'Brightness',
                  Icons.brightness_6,
                  Colors.amber,
                  onReadBrightness,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReadButton(
                  context,
                  'Color Temp',
                  Icons.thermostat,
                  Colors.orange,
                  onReadColorTemperature,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildReadButton(
                  context,
                  'Color',
                  Icons.palette,
                  Colors.purple,
                  onReadColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label.tr(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.5)),
        backgroundColor: color.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
