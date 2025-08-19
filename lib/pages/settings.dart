import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/main.dart';
import 'base_scaffold.dart';
import '../widgets/widgets.dart';
import '../widgets/settings/gateway_type_card.dart';
import '/utils/internal_page_prefs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.onThemeModeChanged,
    required this.onThemeColorChanged,
    this.embedded = false,
  });
  final Function(bool) onThemeModeChanged;
  final Function(Color) onThemeColorChanged;
  final bool embedded;

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
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const ConnectionMethodSetting(),
          const GatewayTypeCard(),
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
          const SizedBox(height: 12),
          _RememberInternalPageSwitch(),
          const SizedBox(height: 20), // 添加底部间距
        ],
      ),
    );
    if (widget.embedded) return content;
    return BaseScaffold(currentPage: 'Settings', body: content);
  }
}

class _RememberInternalPageSwitch extends StatefulWidget {
  const _RememberInternalPageSwitch();
  @override
  State<_RememberInternalPageSwitch> createState() => _RememberInternalPageSwitchState();
}

class _RememberInternalPageSwitchState extends State<_RememberInternalPageSwitch> {
  final prefs = InternalPagePrefs.instance;
  @override
  void initState() {
    super.initState();
    prefs.addListener(_onChanged);
    if (!prefs.loaded) {
      prefs.load();
    }
  }

  @override
  void dispose() {
    prefs.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text('记住上次功能区页面'),
      subtitle: Text('开启后，大尺寸模式重新进入会定位到上次停留的内部页面'),
      value: prefs.remember,
      onChanged: (v) => prefs.setRemember(v),
    );
  }
}
