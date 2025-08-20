import 'package:flutter/material.dart';
import '/toast.dart';
import 'package:easy_localization/easy_localization.dart';

class ToastTestButtonsWidget extends StatelessWidget {
  const ToastTestButtonsWidget({super.key});

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
            children: [
              Icon(
                Icons.notifications_active,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'toast.test.title'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToastButton(
                context,
                'common.loading',
                Icons.hourglass_empty,
                Colors.blue,
                () => ToastManager().showLoadingToast('common.loading'.tr()),
              ),
              _buildToastButton(
                context,
                'common.done',
                Icons.check_circle,
                Colors.green,
                () => ToastManager().showDoneToast('common.done'.tr()),
              ),
              _buildToastButton(
                context,
                'common.error',
                Icons.error,
                Colors.red,
                () => ToastManager().showErrorToast('common.error'.tr()),
              ),
              _buildToastButton(
                context,
                'common.warning',
                Icons.warning,
                Colors.orange,
                () => ToastManager().showWarningToast('common.warning'.tr()),
              ),
              _buildToastButton(
                context,
                'common.info',
                Icons.info,
                Colors.blue,
                () => ToastManager().showInfoToast('common.info'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToastButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label.tr(),
        style: const TextStyle(fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 0,
        minimumSize: const Size(0, 36),
      ),
    );
  }
}
