import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../dali/dali.dart';
import '../../utils/device_info_store.dart';

class FadeControlWidget extends StatefulWidget {
  const FadeControlWidget({super.key});

  @override
  State<FadeControlWidget> createState() => _FadeControlWidgetState();
}

class _FadeControlWidgetState extends State<FadeControlWidget> {
  final store = DeviceInfoStore.instance;
  int? _time;
  int? _rate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _syncFromStore();
    store.addListener(_onStore);
  }

  void _onStore() {
    if (!mounted) return;
    _syncFromStore();
  }

  void _syncFromStore() {
    final a = Dali.instance.base!.selectedAddress;
    final info = store.get(a);
    setState(() {
      _time = info?.fadeTime;
      _rate = info?.fadeRate;
    });
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    super.dispose();
  }

  Future<void> _setTime(int v) async {
    final a = Dali.instance.base!.selectedAddress;
    setState(() => _busy = true);
    try {
      await Dali.instance.base!.setFadeTime(a, v);
      await store.refresh(a);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRate(int v) async {
    final a = Dali.instance.base!.selectedAddress;
    setState(() => _busy = true);
    try {
      await Dali.instance.base!.setFadeRate(a, v);
      await store.refresh(a);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Dali.instance.base!.selectedAddress;
    final info = store.get(a);
    final time = _time;
    final rate = _rate;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('fade.title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'common.refresh'.tr(),
                  onPressed: _busy ? null : () => store.refresh(a),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _LabeledSlider(
              label: 'fade.time'.tr(),
              value: (time ?? 0).toDouble(),
              min: 0,
              max: 255,
              enabled: info != null,
              onChanged: (v) => setState(() => _time = v.round()),
              onChangeEnd: (v) => _setTime(v.round()),
              display: time == null ? '—' : '$time',
            ),
            const SizedBox(height: 8),
            _LabeledSlider(
              label: 'fade.rate'.tr(),
              value: (rate ?? 0).toDouble(),
              min: 0,
              max: 255,
              enabled: info != null,
              onChanged: (v) => setState(() => _rate = v.round()),
              onChangeEnd: (v) => _setRate(v.round()),
              display: rate == null ? '—' : '$rate',
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String display;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.display,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label),
              const Spacer(),
              Text(display, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? onChangeEnd : null,
          ),
        ],
      ),
    );
  }
}
