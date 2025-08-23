import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dalimaster/dali/log.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class LogLevelSetting extends StatefulWidget {
  const LogLevelSetting({super.key});

  @override
  State<LogLevelSetting> createState() => _LogLevelSettingState();
}

class _LogLevelSettingState extends State<LogLevelSetting> {
  LogLevel _selected = DaliLog.instance.currentLevel;

  @override
  void initState() {
    super.initState();
    // ensure DaliLog is initialized and listen for changes
    DaliLog.instance.init().then((_) {
      if (mounted) setState(() => _selected = DaliLog.instance.currentLevel);
    });
    DaliLog.instance.levelStream.listen((level) {
      if (mounted) setState(() => _selected = level);
    });
  }

  void _set(LogLevel l) {
    DaliLog.instance.setLevel(l);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.log_level.title',
        subtitle: 'settings.log_level.subtitle',
        icon: Icons.bug_report,
        control: DropdownButton<LogLevel>(
          value: _selected,
          onChanged: (v) {
            if (v != null) _set(v);
          },
          items: [
            DropdownMenuItem(
              value: LogLevel.debug,
              child: Text('settings.log_level.debug').tr(),
            ),
            DropdownMenuItem(
              value: LogLevel.info,
              child: Text('settings.log_level.info').tr(),
            ),
            DropdownMenuItem(
              value: LogLevel.warning,
              child: Text('settings.log_level.warning').tr(),
            ),
            DropdownMenuItem(
              value: LogLevel.error,
              child: Text('settings.log_level.error').tr(),
            ),
          ],
        ),
      ),
    );
  }
}
