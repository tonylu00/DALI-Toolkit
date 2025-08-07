import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/main.dart';
import 'base_scaffold.dart';
import '../widgets/widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onThemeModeChanged,
    required this.onThemeColorChanged,
  });
  final Function(bool) onThemeModeChanged;
  final Function(Color) onThemeColorChanged;

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  bool _isDarkMode = isDarkMode; // Default Dark Mode state

  @override
  void initState() {
    super.initState();
    _loadDarkModeState();
  }

  Future<void> _loadDarkModeState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      currentPage: 'Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const ConnectionMethodSetting(),
            const DimmingCurveSetting(),
            ThemeColorSetting(
              onThemeColorChanged: widget.onThemeColorChanged,
            ),
            DarkModeSetting(
              onThemeModeChanged: widget.onThemeModeChanged,
              initialValue: _isDarkMode,
            ),
            const LanguageSetting(),
            const DelaysSetting(),
            const AddressingSettings(),
            const SizedBox(height: 20), // 添加底部间距
          ],
        ),
      ),
    );
  }
}
