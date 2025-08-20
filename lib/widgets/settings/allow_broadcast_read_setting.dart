import 'package:flutter/material.dart';
import '../../utils/broadcast_read_prefs.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class AllowBroadcastReadSetting extends StatefulWidget {
  const AllowBroadcastReadSetting({super.key});

  @override
  State<AllowBroadcastReadSetting> createState() => _AllowBroadcastReadSettingState();
}

class _AllowBroadcastReadSettingState extends State<AllowBroadcastReadSetting> {
  final prefs = BroadcastReadPrefs.instance;

  @override
  void initState() {
    super.initState();
    prefs.addListener(_onChanged);
    prefs.load();
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
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.allowBroadcastRead.title',
        subtitle: 'settings.allowBroadcastRead.subtitle',
        icon: Icons.wifi_tethering,
        control: Switch(
          value: prefs.allow,
          onChanged: (v) => prefs.setAllow(v),
        ),
      ),
    );
  }
}
