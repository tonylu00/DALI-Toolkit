import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class DarkModeSetting extends StatefulWidget {
  final Function(bool) onThemeModeChanged;
  final bool initialValue;

  const DarkModeSetting({
    super.key,
    required this.onThemeModeChanged,
    required this.initialValue,
  });

  @override
  DarkModeSettingState createState() => DarkModeSettingState();
}

class DarkModeSettingState extends State<DarkModeSetting> {
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialValue;
    _loadDarkModeState();
  }

  Future<void> _loadDarkModeState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveDarkModeState(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'Dark Mode',
        icon: Icons.dark_mode,
        subtitle: 'Toggle between light and dark theme',
        control: Switch(
          value: _isDarkMode,
          onChanged: (value) {
            setState(() {
              _isDarkMode = value;
            });
            _saveDarkModeState(value);
            widget.onThemeModeChanged(value);
          },
        ),
      ),
    );
  }
}
