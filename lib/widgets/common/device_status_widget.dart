import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '/connection/manager.dart';
import 'package:easy_localization/easy_localization.dart';

class DeviceStatusWidget extends StatelessWidget {
  const DeviceStatusWidget({super.key, this.clickable = true});

  final bool clickable;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Dali.instance.addr!.selectedDeviceStream,
      builder: (context, snapshot) {
        return InkWell(
          onTap: !clickable
              ? null
              : () {
                  // 仅打开设备列表，不自动扫描
                  if (!ConnectionManager.instance.ensureReadyForOperation()) return;
                  Dali.instance.addr?.openDeviceSelectionPage(context);
                },
          borderRadius: BorderRadius.circular(12.0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.devices,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${'Selected Address'.tr()}: ${snapshot.hasData ? snapshot.data : Dali.instance.base!.selectedAddress}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
