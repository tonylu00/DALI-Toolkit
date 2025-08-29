import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../utils/device_info_store.dart';
import '../../dali/dali.dart';

class StatusBitsWidget extends StatefulWidget {
  const StatusBitsWidget({super.key});

  @override
  State<StatusBitsWidget> createState() => _StatusBitsWidgetState();
}

class _StatusBitsWidgetState extends State<StatusBitsWidget> {
  final store = DeviceInfoStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final a = Dali.instance.base!.selectedAddress;
    final info = store.get(a);
    final status = info?.status;
    final tiles = _buildTiles(context, status);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('status.title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'common.refresh'.tr(),
                  onPressed: () => store.refresh(a),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tiles,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTiles(BuildContext ctx, int? status) {
    final items = <_BitItem>[
      _BitItem('gearFail', 0x80),
      _BitItem('lampFail', 0x02),
      _BitItem('lampOn', 0x04),
      _BitItem('limit', 0x08),
      _BitItem('fadingDone', 0x10, invertColor: true),
      _BitItem('reset', 0x20, invertColor: true),
      _BitItem('missingAddr', 0x40),
    ];

    Color colorFor(bool? active, {bool invert = false}) {
      if (active == null) return Colors.transparent;
      if (invert) {
        // invert: active=true means normal
        return active ? Colors.green : Colors.red;
      }
      return active ? Colors.red : Colors.green;
    }

    return items.map((e) {
      final has = status == null ? null : ((status & e.mask) == e.mask);
      final bg = colorFor(has, invert: e.invertColor);
      final onBg = bg == Colors.transparent
          ? Theme.of(ctx).colorScheme.onSurface
          : Theme.of(ctx).colorScheme.onPrimary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg == Colors.transparent ? null : bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (bg == Colors.transparent ? Theme.of(ctx).colorScheme.outline : bg)
                .withValues(alpha: 0.7),
          ),
        ),
        child: Text(
          e.key.tr(args: []),
          style: TextStyle(
            color: onBg,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }).toList();
  }
}

class _BitItem {
  final String key;
  final int mask;
  final bool invertColor;
  _BitItem(this.key, this.mask, {this.invertColor = false});
}
