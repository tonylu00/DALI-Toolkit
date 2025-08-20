import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_card.dart';
import 'settings_item.dart';
import 'settings_option_button.dart';

class DimmingCurveSetting extends StatefulWidget {
  const DimmingCurveSetting({super.key});

  @override
  DimmingCurveSettingState createState() => DimmingCurveSettingState();
}

class DimmingCurveSettingState extends State<DimmingCurveSetting> {
  String _selectedDimmingCurve = 'linear';

  @override
  void initState() {
    super.initState();
    _loadSelectedDimmingCurve();
  }

  Future<void> _loadSelectedDimmingCurve() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDimmingCurve = prefs.getString('dimmingCurve') ?? 'linear';
    });
  }

  Future<void> _saveSelectedDimmingCurve(String curve) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dimmingCurve', curve);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.dimming_curve.title',
        icon: Icons.tune,
        subtitle: 'settings.dimming_curve.subtitle',
        control: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsOptionButton(
              label: 'curve.linear',
              width: 100,
              isSelected: _selectedDimmingCurve == 'linear',
              onTap: () => _selectDimmingCurve('linear'),
            ),
            SettingsOptionButton(
              label: 'curve.logarithmic',
              width: 100,
              isSelected: _selectedDimmingCurve == 'logarithmic',
              onTap: () => _selectDimmingCurve('logarithmic'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectDimmingCurve(String curve) {
    setState(() {
      _selectedDimmingCurve = curve;
    });
    _saveSelectedDimmingCurve(curve);
  }
}
