import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart'; // still used for hintText translations
import 'settings_card.dart';
import 'settings_item.dart';

class DelaysSetting extends StatefulWidget {
  const DelaysSetting({super.key});

  @override
  DelaysSettingState createState() => DelaysSettingState();
}

class DelaysSettingState extends State<DelaysSetting> {
  final TextEditingController _sendDelaysController = TextEditingController();
  final TextEditingController _queryDelaysController = TextEditingController();
  final TextEditingController _extDelaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDelays();
  }

  @override
  void dispose() {
    _sendDelaysController.dispose();
    _queryDelaysController.dispose();
    _extDelaysController.dispose();
    super.dispose();
  }

  Future<void> _loadDelays() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sendDelaysController.text =
          (prefs.getInt('sendDelays') ?? 50).toString();
      _queryDelaysController.text =
          (prefs.getInt('queryDelays') ?? 50).toString();
      _extDelaysController.text = (prefs.getInt('extDelays') ?? 100).toString();
    });
  }

  Future<void> _saveDelays() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sendDelaysController.text.isNotEmpty) {
      await prefs.setInt(
          'sendDelays', int.tryParse(_sendDelaysController.text) ?? 50);
    }
    if (_queryDelaysController.text.isNotEmpty) {
      await prefs.setInt(
          'queryDelays', int.tryParse(_queryDelaysController.text) ?? 50);
    }
    if (_extDelaysController.text.isNotEmpty) {
      await prefs.setInt(
          'extDelays', int.tryParse(_extDelaysController.text) ?? 100);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SettingsCard(
          child: SettingsItem(
            title: 'delays.send.title',
            icon: Icons.send,
            subtitle: 'settings.delays.send.subtitle',
            control: SizedBox(
              width: 100,
              child: TextField(
                controller: _sendDelaysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'delays.send.title'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  _saveDelays();
                },
              ),
            ),
          ),
        ),
        SettingsCard(
          child: SettingsItem(
            title: 'delays.query.title',
            icon: Icons.query_stats,
            subtitle: 'settings.delays.query.subtitle',
            control: SizedBox(
              width: 100,
              child: TextField(
                controller: _queryDelaysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'delays.query.title'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  _saveDelays();
                },
              ),
            ),
          ),
        ),
        SettingsCard(
          child: SettingsItem(
            title: 'delays.extend.title',
            icon: Icons.access_time,
            subtitle: 'settings.delays.extend.subtitle',
            control: SizedBox(
              width: 100,
              child: TextField(
                controller: _extDelaysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'delays.extend.title'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  _saveDelays();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
