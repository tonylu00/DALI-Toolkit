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
  String _selectedDimmingCurve = 'Linear';

  @override
  void initState() {
    super.initState();
    _loadSelectedDimmingCurve();
  }

  Future<void> _loadSelectedDimmingCurve() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDimmingCurve = prefs.getString('dimmingCurve') ?? 'Linear';
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
        title: 'Dimming Curve',
        icon: Icons.tune,
        subtitle: 'Choose brightness curve type',
        control: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsOptionButton(
              label: 'Linear',
              width: 100,
              isSelected: _selectedDimmingCurve == 'Linear',
              onTap: () => _selectDimmingCurve('Linear'),
            ),
            SettingsOptionButton(
              label: 'Logarithmic',
              width: 100,
              isSelected: _selectedDimmingCurve == 'Logarithmic',
              onTap: () => _selectDimmingCurve('Logarithmic'),
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
