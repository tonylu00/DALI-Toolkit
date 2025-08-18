import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '/dali/log.dart';
import '/connection/manager.dart';
import 'package:easy_localization/easy_localization.dart';

class DeviceControlButtonsWidget extends StatelessWidget {
  const DeviceControlButtonsWidget({super.key});

  bool _checkDeviceConnection() => ConnectionManager.instance.ensureReadyForOperation();

  @override
  Widget build(BuildContext context) {
    final log = DaliLog.instance;

    return Column(
      children: [
        // 主要控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _buildElevatedButton(
              context: context,
              onPressed: () {
                if (!_checkDeviceConnection()) return;
                Dali.instance.base?.recallMaxLevel(Dali.instance.base!.selectedAddress);
              },
              label: 'ON',
              icon: Icons.lightbulb,
              color: Colors.green,
            ),
            _buildElevatedButton(
              context: context,
              onPressed: () {
                if (!_checkDeviceConnection()) return;
                Dali.instance.base?.off(Dali.instance.base!.selectedAddress);
              },
              label: 'OFF',
              icon: Icons.lightbulb_outline,
              color: Colors.red,
            ),
            _buildElevatedButton(
              context: context,
              onPressed: () {
                if (!_checkDeviceConnection()) return;
                Dali.instance.addr?.resetAndAllocAddr();
                log.showLogDialog(context, 'Log', clear: true, onCanceled: () {
                  Dali.instance.addr?.stopAllocAddr();
                });
              },
              label: 'Addressing',
              icon: Icons.settings_ethernet,
              color: Colors.blue,
            ),
            _buildElevatedButton(
              context: context,
              onPressed: () {
                if (!_checkDeviceConnection()) return;
                Dali.instance.addr?.searchAddr();
                Dali.instance.addr?.showDevicesDialog(context);
              },
              label: 'Search',
              icon: Icons.search,
              color: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 辅助控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            _buildSecondaryButton(
              context: context,
              onPressed: () {
                if (!_checkDeviceConnection()) return;
                Dali.instance.base?.reset(Dali.instance.base!.selectedAddress);
              },
              label: 'Reset',
              icon: Icons.restart_alt,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildElevatedButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            elevation: 0,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(
            label.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label.tr(),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
