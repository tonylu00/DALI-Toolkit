import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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
    // Web 环境不支持 Platform.isIOS方法；同时 iOS 也不支持 USB
    if (!kIsWeb && !Platform.isIOS) {
      methods.add('USB');
    }
    if (kIsWeb) {
      methods.add('USB');
    }
    // 除 web 外都支持 IP
    if (!kIsWeb) {
      methods.add('IP');
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
        title: 'connection.method',
        icon: Icons.settings_ethernet,
        subtitle: 'settings.connection.subtitle',
        control: SizedBox(
          width: 120,
          child: DropdownButton<String>(
            value: _selectedConnectionMethod,
            isExpanded: true,
            underline: Container(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
            items: _availableConnectionMethods
                .map<DropdownMenuItem<String>>((String method) {
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
    // 兼容旧 TCP/UDP -> IP
    String stored = method;
    if (method == 'TCP' || method == 'UDP') stored = 'IP';
    _saveSelectedConnectionMethod(stored);
    ConnectionManager.instance.init();
  }
}
