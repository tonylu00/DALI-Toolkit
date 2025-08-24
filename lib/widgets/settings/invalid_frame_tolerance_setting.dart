import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class InvalidFrameToleranceSetting extends StatefulWidget {
  const InvalidFrameToleranceSetting({super.key});

  @override
  State<InvalidFrameToleranceSetting> createState() => _InvalidFrameToleranceSettingState();
}

class _InvalidFrameToleranceSettingState extends State<InvalidFrameToleranceSetting> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _controller.text = (prefs.getInt('invalidFrameTolerance') ?? 1).toString();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final parsed = int.tryParse(_controller.text);
    final value = (parsed == null || parsed < 0) ? 0 : parsed;
    await prefs.setInt('invalidFrameTolerance', value);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.invalidFrameTolerance.title',
        subtitle: 'settings.invalidFrameTolerance.subtitle',
        icon: Icons.shield,
        control: SizedBox(
          width: 100,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'settings.invalidFrameTolerance.title'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            onChanged: (_) => _save(),
          ),
        ),
      ),
    );
  }
}
