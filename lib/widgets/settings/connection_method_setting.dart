import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '/connection/manager.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class ConnectionMethodSetting extends StatefulWidget {
  const ConnectionMethodSetting({super.key});

  @override
  ConnectionMethodSettingState createState() => ConnectionMethodSettingState();
}

class ConnectionMethodSettingState extends State<ConnectionMethodSetting> {
  String _selectedConnectionMethod = 'BLE';

  List<String> get _availableConnectionMethods {
    List<String> methods = ['BLE'];
    if (!Platform.isIOS) {
      methods.add('USB');
    }
    if (Platform.isAndroid || Platform.isLinux) {
      methods.add('TCP');
    }
    return methods;
  }

  @override
  void initState() {
    super.initState();
    _loadSelectedConnectionMethod();
  }

  Future<void> _loadSelectedConnectionMethod() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedConnectionMethod = prefs.getString('connectionMethod') ?? 'BLE';
    });
  }

  Future<void> _saveSelectedConnectionMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connectionMethod', method);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'Connection Method',
        icon: Icons.settings_ethernet,
        subtitle: 'Select your preferred connection method',
        control: SizedBox(
          width: 120,
          child: DropdownButton<String>(
            value: _selectedConnectionMethod,
            isExpanded: true,
            underline: Container(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
            items: _availableConnectionMethods.map<DropdownMenuItem<String>>((String method) {
              return DropdownMenuItem<String>(
                value: method,
                child: Text(
                  method,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                _selectConnectionMethod(newValue);
              }
            },
          ),
        ),
      ),
    );
  }

  void _selectConnectionMethod(String method) {
    setState(() {
      _selectedConnectionMethod = method;
    });
    _saveSelectedConnectionMethod(method);
    ConnectionManager.instance.init();
  }
}
