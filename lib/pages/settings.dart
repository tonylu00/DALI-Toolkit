import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../dali/color.dart';
import '/connection/manager.dart';
import '/main.dart';
import 'base_scaffold.dart';
import 'package:easy_localization/easy_localization.dart';
import 'color_picker.dart'; // Import MyColorPicker

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
  String _selectedConnectionMethod = 'BLE'; // Default selected method
  String _selectedDimmingCurve = 'Linear'; // Default selected dimming curve
  bool _isDarkMode = isDarkMode; // Default Dark Mode state
  bool _removeAddr = false; // Default removeAddr state
  bool _closeLight = false; // Default closeLight state

  final TextEditingController _sendDelaysController = TextEditingController();
  final TextEditingController _queryDelaysController = TextEditingController();
  final TextEditingController _extDelaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSelectedConnectionMethod();
    _loadSelectedDimmingCurve();
    _loadSelectedThemeColor();
    _loadDarkModeState();
    _loadDelays();
    _loadRemoveAddrState();
    _loadCloseLightState();
  }

  Future<void> _loadRemoveAddrState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _removeAddr = prefs.getBool('removeAddr') ?? false;
    });
  }

  Future<void> _loadCloseLightState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _closeLight = prefs.getBool('closeLight') ?? false;
    });
  }

  Future<void> _saveRemoveAddrState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('removeAddr', value);
  }

  Future<void> _saveCloseLightState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('closeLight', value);
  }

  Future<void> _loadDelays() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sendDelaysController.text = (prefs.getInt('sendDelays') ?? 50).toString();
      _queryDelaysController.text = (prefs.getInt('queryDelays') ?? 50).toString();
      _extDelaysController.text = (prefs.getInt('extDelays') ?? 100).toString();
    });
  }

  Future<void> _saveDelays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sendDelays', int.parse(_sendDelaysController.text));
    await prefs.setInt('queryDelays', int.parse(_queryDelaysController.text));
    await prefs.setInt('extDelays', int.parse(_extDelaysController.text));
  }

  Future<void> _loadSelectedConnectionMethod() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedConnectionMethod = prefs.getString('connectionMethod') ?? 'BLE';
    });
  }

  Future<void> _loadSelectedDimmingCurve() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDimmingCurve = prefs.getString('dimmingCurve') ?? 'Linear';
    });
  }

  Future<void> _loadSelectedThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      int? colorValue = prefs.getInt('themeColor');
      if (colorValue != null) {
        widget.onThemeColorChanged(Color(colorValue));
      }
    });
  }

  Future<void> _loadDarkModeState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveSelectedConnectionMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connectionMethod', method);
  }

  Future<void> _saveSelectedDimmingCurve(String curve) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dimmingCurve', curve);
  }

  Future<void> _saveSelectedThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', DaliColor.toInt(color));
  }

  Future<void> _saveDarkModeState(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      currentPage: 'Settings',
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Connection Method',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                Row(
                  children: [
                    _buildConnectionOption('BLE'),
                    _buildConnectionOption('TCP'),
                    if (!Platform.isIOS) _buildConnectionOption('USB'),
                  ],
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dimming Curve',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                Row(
                  children: [
                    _buildDimmingCurveOption('Linear'),
                    _buildDimmingCurveOption('Logarithmic'),
                  ],
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Theme Color',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                MyColorPicker(
                  onColorChanged: (color) {
                    setState(() {
                    });
                    _saveSelectedThemeColor(color);
                    widget.onThemeColorChanged(color);
                  },
                  defaultColor: Theme.of(context).colorScheme.primary
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dark Mode',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                Switch(
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                    _saveDarkModeState(value);
                    widget.onThemeModeChanged(value);
                  },
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Language',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                DropdownButton<Locale?>(
                  value: context.locale,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text('System Default').tr(),
                    ),
                    ...context.supportedLocales.map((locale) {
                      return DropdownMenuItem(
                        value: locale,
                        child: Text(locale.toLanguageTag()),
                      );
                    }),
                  ],
                  onChanged: (Locale? locale) {
                    if (locale == null) {
                      context.resetLocale();
                      return;
                    }
                    context.setLocale(locale);
                  },
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface, thickness: 2.5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Send Delays',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _sendDelaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Send Delays'.tr(),
                    ),
                    onChanged: (value) {
                      _saveDelays();
                    },
                  ),
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Query Delays',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _queryDelaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Query Delays'.tr(),
                    ),
                    onChanged: (value) {
                      _saveDelays();
                    },
                  ),
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Extend Delays',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _extDelaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Extend Delays'.tr(),
                    ),
                    onChanged: (value) {
                      _saveDelays();
                    },
                  ),
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface, thickness: 2.5),
            Text(
              'Addressing Settings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ).tr(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Remove all addresses',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                Switch(
                  value: _removeAddr,
                  onChanged: (value) {
                    setState(() {
                      _removeAddr = value;
                    });
                    _saveRemoveAddrState(value);
                  },
                ),
              ],
            ),
            Divider(height: 16.0, color: Theme.of(context).colorScheme.onSurface),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Close Light',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ).tr(),
                Switch(
                  value: _closeLight,
                  onChanged: (value) {
                    setState(() {
                      _closeLight = value;
                    });
                    _saveCloseLightState(value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionOption(String method) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedConnectionMethod = method;
        });
        _saveSelectedConnectionMethod(method);
        ConnectionManager.instance.init();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12.0),
        padding: const EdgeInsets.all(12.0),
        width: 80.0,
        decoration: BoxDecoration(
          color: _selectedConnectionMethod == method ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onInverseSurface,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Center(child: Text(method, style: TextStyle(
            fontSize: 16,
            color: _selectedConnectionMethod == method ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
        )).tr()),
      ),
    );
  }

  Widget _buildDimmingCurveOption(String curve) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDimmingCurve = curve;
        });
        _saveSelectedDimmingCurve(curve);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12.0),
        padding: const EdgeInsets.all(12.0),
        width: 120.0,
        decoration: BoxDecoration(
          color: _selectedDimmingCurve == curve ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onInverseSurface,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Center(child: Text(curve, style: TextStyle(
          fontSize: 16,
          color: _selectedDimmingCurve == curve ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
        )).tr()),
      ),
    );
  }
}