import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../dali/dali.dart';
import 'color_picker.dart';

class SceneEditorPage extends StatefulWidget {
  const SceneEditorPage({super.key});

  @override
  State<SceneEditorPage> createState() => _SceneEditorPageState();
}

class _SceneEditorPageState extends State<SceneEditorPage> {
  int _scene = 0;
  int _brightness = 128; // 0..254
  bool _useCCT = true; // true: color temperature, false: color
  int _cct = 3000; // Kelvin
  Color _color = const Color(0xFFFF0000);
  bool _busy = false;

  Future<void> _save() async {
    final base = Dali.instance.base!;
    final dt8 = Dali.instance.dt8!;
    final a = base.selectedAddress;
    setState(() => _busy = true);
    try {
      if (_useCCT) {
        await dt8.setColorTemperature(a, _cct);
      } else {
        // Convert Color -> RGB ints (0..255)
        final r = (_color.r * 255.0).round();
        final g = (_color.g * 255.0).round();
        final b = (_color.b * 255.0).round();
        await dt8.setColourRGB(a, r, g, b);
      }
      // Write brightness to DTR and store to scene
      await base.setDTR(_brightness.clamp(0, 254));
      await base.storeDTRAsSceneBright(a, _scene);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('scene.editor.title'.tr()),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save),
            label: Text('common.save').tr(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Scene selector 0..15
          Row(
            children: [
              Text('scene.label'.tr()),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _scene,
                items: List.generate(16, (i) => DropdownMenuItem(value: i, child: Text('S$i'))),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          _scene = v ?? 0;
                        }),
              ),
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Brightness slider
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('brightness.label'.tr()),
                  Slider(
                    value: _brightness.toDouble(),
                    min: 0,
                    max: 254,
                    divisions: 254,
                    label: '$_brightness',
                    onChanged: _busy ? null : (v) => setState(() => _brightness = v.round()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Mode toggle
          SegmentedButton<bool>(
            segments: [
              ButtonSegment<bool>(value: true, label: Text('scene.editor.mode.ct'.tr())),
              ButtonSegment<bool>(value: false, label: Text('scene.editor.mode.color'.tr())),
            ],
            selected: {_useCCT},
            onSelectionChanged: _busy ? null : (s) => setState(() => _useCCT = s.first),
          ),

          const SizedBox(height: 12),

          if (_useCCT)
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('scene.editor.ct.label'.tr()),
                    Slider(
                      value: _cct.toDouble(),
                      min: 1500,
                      max: 10000,
                      divisions: 85,
                      label: '$_cct K',
                      onChanged: _busy ? null : (v) => setState(() => _cct = v.round()),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('scene.editor.color.label'.tr()),
                    const SizedBox(height: 8),
                    MyColorPicker(
                      onColorChanged: (c) => setState(() => _color = c),
                      defaultColor: _color,
                      enableAlpha: false,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
