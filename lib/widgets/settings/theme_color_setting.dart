import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/dali/color.dart';
import '/pages/color_picker.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class ThemeColorSetting extends StatefulWidget {
  final Function(Color) onThemeColorChanged;

  const ThemeColorSetting({
    super.key,
    required this.onThemeColorChanged,
  });

  @override
  ThemeColorSettingState createState() => ThemeColorSettingState();
}

class ThemeColorSettingState extends State<ThemeColorSetting> {
  @override
  void initState() {
    super.initState();
    _loadSelectedThemeColor();
  }

  Future<void> _loadSelectedThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    int? colorValue = prefs.getInt('themeColor');
    if (colorValue != null) {
      widget.onThemeColorChanged(Color(colorValue));
    }
  }

  Future<void> _saveSelectedThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', DaliColor.toInt(color));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'theme.color.title',
        icon: Icons.palette,
        subtitle: 'settings.theme_color.subtitle',
        control: MyColorPicker(
          onColorChanged: (color) {
            _saveSelectedThemeColor(color);
            widget.onThemeColorChanged(color);
          },
          defaultColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
