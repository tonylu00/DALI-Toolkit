import 'package:flutter/material.dart';
import '/dali/dali.dart';
import '/connection/manager.dart';
import 'package:easy_localization/easy_localization.dart';
import '/dali/errors.dart';
import '/toast.dart';

class GroupControlWidget extends StatefulWidget {
  final List<bool> groupCheckboxes;
  final ValueChanged<List<bool>> onGroupCheckboxesChanged;
  final bool canRead;

  const GroupControlWidget({
    super.key,
    required this.groupCheckboxes,
    required this.canRead,
    required this.onGroupCheckboxesChanged,
  });

  @override
  State<GroupControlWidget> createState() => _GroupControlWidgetState();
}

class _GroupControlWidgetState extends State<GroupControlWidget> {
  bool _checkDeviceConnection() => ConnectionManager.instance.ensureReadyForOperation();

  Future<void> _readGroup() async {
    if (!_checkDeviceConnection()) return;
    if (Dali.instance.base!.selectedAddress > 63) {
      ToastManager().showErrorToast('group.read.unsupported'.tr());
      return;
    }
    final group = await daliSafeToast<int>(() async {
      return await Dali.instance.base!.getGroup(Dali.instance.base!.selectedAddress);
    });
    if (group == null) return;
    List<bool> newCheckboxes = List.from(widget.groupCheckboxes);
    for (int i = 0; i < 16; i++) {
      newCheckboxes[i] = (group & (1 << i)) != 0;
    }
    widget.onGroupCheckboxesChanged(newCheckboxes);
  }

  Future<void> _writeGroup() async {
    if (!_checkDeviceConnection()) return;
    int group = 0;
    for (int i = 0; i < 16; i++) {
      if (widget.groupCheckboxes[i]) group |= (1 << i);
    }
    final _ = await daliSafeToast<void>(() async {
      await Dali.instance.base!.setGroup(Dali.instance.base!.selectedAddress, group);
    });
    if (mounted) {
      ToastManager().showDoneToast('group.write.success'.tr());
    }
  }

  void _onCheckboxChanged(int index, bool? value) {
    List<bool> newCheckboxes = List.from(widget.groupCheckboxes);
    newCheckboxes[index] = value ?? false;
    widget.onGroupCheckboxesChanged(newCheckboxes);
  }

  void _clearAll() {
    List<bool> newCheckboxes = List.generate(16, (_) => false);
    widget.onGroupCheckboxesChanged(newCheckboxes);
  }

  void _selectAll() {
    List<bool> newCheckboxes = List.generate(16, (_) => true);
    widget.onGroupCheckboxesChanged(newCheckboxes);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = widget.groupCheckboxes.where((selected) => selected).length;

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
                    Icons.group_work,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'group.config.title'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedCount/16',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 快捷操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: Text('common.clear_all'.tr()),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectAll,
                  icon: const Icon(Icons.select_all, size: 16),
                  label: Text('common.select_all'.tr()),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 组选择网格
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 16,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 4.0,
                crossAxisSpacing: 4.0,
                childAspectRatio: 0.7,
                mainAxisExtent: 60.0,
              ),
              itemBuilder: (context, index) {
                return _buildGroupCheckbox(index);
              },
            ),
          ),
          const SizedBox(height: 16),
          // 读写操作按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.canRead ? _readGroup : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text('common.read'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _writeGroup,
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text('common.write'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCheckbox(int index) {
    final isSelected = widget.groupCheckboxes[index];

    return GestureDetector(
      onTap: () => _onCheckboxChanged(index, !isSelected),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 1),
            Flexible(
              child: Transform.scale(
                scale: 0.9,
                child: Checkbox(
                  value: isSelected,
                  onChanged: (value) => _onCheckboxChanged(index, value),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
