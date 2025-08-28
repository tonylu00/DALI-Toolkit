import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class ResponseWindowSetting extends StatefulWidget {
  const ResponseWindowSetting({super.key});

  @override
  State<ResponseWindowSetting> createState() => _ResponseWindowSettingState();
}

class _ResponseWindowSettingState extends State<ResponseWindowSetting> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('busMonitor.responseWindowMs') ?? 100;
    if (!mounted) return;
    setState(() => _controller.text = ms.toString());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final v = int.tryParse(_controller.text) ?? 100;
    await prefs.setInt('busMonitor.responseWindowMs', v);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'Bus monitor response window',
        subtitle: 'Associate 1-byte back frames to recent query within this window (ms)'.trim(),
        icon: Icons.timelapse,
        control: SizedBox(
          width: 120,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '100',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (_) => _save(),
            onChanged: (_) => _save(),
          ),
        ),
      ),
    );
  }
}
