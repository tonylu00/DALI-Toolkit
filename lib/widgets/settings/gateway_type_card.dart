import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../connection/manager.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class GatewayTypeCard extends StatelessWidget {
  const GatewayTypeCard({super.key});

  String _typeLabel(int t) {
    switch (t) {
      case -1:
        return 'Unknown';
      case 0:
        return 'Type 0 (USB)';
      case 1:
        return 'Type 1 (Legacy)';
      case 2:
        return 'Type 2 (New)';
      default:
        return 't=$t';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = ConnectionManager.instance;
    return AnimatedBuilder(
      animation: mgr,
      builder: (ctx, _) {
        final label = _typeLabel(mgr.gatewayType);
        return SettingsCard(
          child: SettingsItem(
            title: 'Gateway Type',
            icon: Icons.usb_rounded,
            subtitle: 'Display and re-detect gateway type',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    mgr.updateGatewayType(-1);
                    await mgr.ensureGatewayType();
                  },
                  child: const Text('Re-detect').tr(),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
