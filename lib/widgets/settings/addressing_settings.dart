import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'settings_card.dart';

class AddressingSettings extends StatefulWidget {
  const AddressingSettings({super.key});

  @override
  AddressingSettingsState createState() => AddressingSettingsState();
}

class AddressingSettingsState extends State<AddressingSettings> {
  bool _removeAddr = false;
  bool _closeLight = false;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题部分
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Icon(
                  Icons.settings_applications,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Addressing Settings'.tr(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 第一个选项
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Icon(
                  Icons.clear_all,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remove all addresses'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'settings.addressing.remove.subtitle'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 16),
          // 分隔线
          Container(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          // 第二个选项
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Close Light'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'settings.addressing.close_light.subtitle'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
    );
  }
}
