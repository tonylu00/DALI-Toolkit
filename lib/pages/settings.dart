import 'package:dalimaster/toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/main.dart';
import 'base_scaffold.dart';
import '../widgets/widgets.dart';
import '../widgets/settings/gateway_type_card.dart';
import '../widgets/settings/auto_reconnect_setting.dart';
import '../widgets/settings/allow_broadcast_read_setting.dart';
import '../widgets/settings/invalid_frame_tolerance_setting.dart';
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
          const LogLevelSetting(),
          const DimmingCurveSetting(),
          const AutoReconnectSetting(),
          ThemeColorSetting(
            onThemeColorChanged: widget.onThemeColorChanged,
          ),
          DarkModeSetting(
            onThemeModeChanged: widget.onThemeModeChanged,
            initialValue: _isDarkMode,
          ),
          const LanguageSetting(),
          const DelaysSetting(),
          const InvalidFrameToleranceSetting(),
          const ResponseWindowSetting(),
          const AddressingSettings(),
          const AllowBroadcastReadSetting(),
          const CrashlyticsReportAllErrorsSetting(),
          if (kDebugMode) const CrashlyticsTestCrashSetting(),
          const ResetAnonymousIdSetting(),
          const SizedBox(height: 12),
          const RememberInternalPageSetting(),
          const SizedBox(height: 20), // 添加底部间距
        ],
      ),
    );
    if (widget.embedded) return content;
    return BaseScaffold(currentPage: 'Settings', body: content);
  }
}

class RememberInternalPageSetting extends StatefulWidget {
  const RememberInternalPageSetting({super.key});
  @override
  State<RememberInternalPageSetting> createState() => _RememberInternalPageSettingState();
}

class _RememberInternalPageSettingState extends State<RememberInternalPageSetting> {
  final prefs = InternalPagePrefs.instance;

  @override
  void initState() {
    super.initState();
    prefs.addListener(_onChanged);
    if (!prefs.loaded) prefs.load();
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
        title: 'settings.remember_internal_page.title',
        subtitle: 'settings.remember_internal_page.subtitle',
        icon: Icons.history_toggle_off,
        control: Switch(
          value: prefs.remember,
          onChanged: (v) => prefs.setRemember(v),
        ),
      ),
    );
  }
}

class CrashlyticsReportAllErrorsSetting extends StatefulWidget {
  const CrashlyticsReportAllErrorsSetting({super.key});

  @override
  State<CrashlyticsReportAllErrorsSetting> createState() =>
      _CrashlyticsReportAllErrorsSettingState();
}

class ResetAnonymousIdSetting extends StatelessWidget {
  const ResetAnonymousIdSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.anonymous_id.reset.title',
        subtitle: 'settings.anonymous_id.reset.subtitle',
        icon: Icons.refresh,
        control: FilledButton.tonal(
          onPressed: () async {
            final newId = await resetAnonymousId();
            ToastManager()
                .showInfoToast('settings.anonymous_id.reset.done'.replaceFirst('{id}', newId));
          },
          child: const Text('common.reset').tr(),
        ),
      ),
    );
  }
}

class _CrashlyticsReportAllErrorsSettingState extends State<CrashlyticsReportAllErrorsSetting> {
  bool _value = reportAllErrors;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _value = prefs.getBool('reportAllErrors') ?? reportAllErrors;
    });
  }

  Future<void> _onChanged(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reportAllErrors', v);
    reportAllErrors = v;
    setState(() {
      _value = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.crashlytics.report_all.title',
        subtitle: 'settings.crashlytics.report_all.subtitle',
        icon: Icons.report_gmailerrorred_outlined,
        control: Switch(
          value: _value,
          onChanged: _onChanged,
        ),
      ),
    );
  }
}

class CrashlyticsTestCrashSetting extends StatelessWidget {
  const CrashlyticsTestCrashSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'settings.crashlytics.test_crash.title',
        subtitle: 'settings.crashlytics.test_crash.subtitle',
        icon: Icons.bug_report_outlined,
        control: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async {
            await FirebaseCrashlytics.instance.log('Debug test crash triggered from Settings');
            // 触发原生崩溃（Android/iOS），用于验证 Crashlytics 集成
            FirebaseCrashlytics.instance.crash();
          },
          child: const Text('Test Crash'),
        ),
      ),
    );
  }
}
