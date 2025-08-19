import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class AutoReconnectSetting extends StatefulWidget {
  const AutoReconnectSetting({super.key});

  @override
  State<AutoReconnectSetting> createState() => _AutoReconnectSettingState();
}

class _AutoReconnectSettingState extends State<AutoReconnectSetting> {
  bool _enabled = true;
  final TextEditingController _intervalController = TextEditingController();
  final TextEditingController _maxAttemptsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enabled = prefs.getBool('autoReconnectEnabled') ?? true;
      _intervalController.text = (prefs.getInt('autoReconnectInterval') ?? 2000).toString();
      _maxAttemptsController.text = (prefs.getInt('autoReconnectMaxAttempts') ?? 5).toString();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoReconnectEnabled', _enabled);
    final interval = int.tryParse(_intervalController.text) ?? 2000;
    final maxAttempts = int.tryParse(_maxAttemptsController.text) ?? 5;
    await prefs.setInt('autoReconnectInterval', interval);
    await prefs.setInt('autoReconnectMaxAttempts', maxAttempts);
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _maxAttemptsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          child: SettingsItem(
            title: 'Auto Reconnect',
            icon: Icons.usb,
            subtitle: 'settings.autoReconnect.subtitle',
            control: Switch(
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                _save();
              },
            ),
          ),
        ),
        if (_enabled) ...[
          SettingsCard(
            child: SettingsItem(
              title: 'Reconnect Interval (ms)',
              icon: Icons.timer,
              subtitle: 'settings.autoReconnect.interval.subtitle',
              control: SizedBox(
                width: 120,
                child: TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Interval'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
            ),
          ),
          SettingsCard(
            child: SettingsItem(
              title: 'Max Attempts',
              icon: Icons.repeat,
              subtitle: 'settings.autoReconnect.maxAttempts.subtitle',
              control: SizedBox(
                width: 120,
                child: TextField(
                  controller: _maxAttemptsController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Attempts'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
