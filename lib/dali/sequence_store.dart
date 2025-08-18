import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'sequence.dart';

/// 序列存储键
const _kSequencesKey = 'command_sequences_v1';

class SequenceRepository {
  SequenceRepository._();
  static final SequenceRepository instance = SequenceRepository._();

  List<CommandSequence> _sequences = [];
  List<CommandSequence> get sequences => List.unmodifiable(_sequences);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSequencesKey);
    if (raw == null || raw.isEmpty) {
      _sequences = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _sequences =
          list.map((e) => CommandSequence.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      _sequences = [];
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _sequences.map((e) => e.toJson()).toList();
    await prefs.setString(_kSequencesKey, jsonEncode(list));
  }

  void add(CommandSequence s) {
    _sequences.add(s);
  }

  void remove(String id) {
    _sequences.removeWhere((e) => e.id == id);
  }

  void replace(CommandSequence s) {
    final idx = _sequences.indexWhere((e) => e.id == s.id);
    if (idx >= 0) {
      _sequences[idx] = s;
    }
  }
}
