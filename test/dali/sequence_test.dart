import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dalimaster/dali/sequence.dart';
import 'package:dalimaster/dali/sequence_store.dart';

void main() {
  group('Sequence model (pure)', () {
    test('serialize and deserialize CommandSequence', () {
      final step = SequenceStep(
        id: 's1',
        type: DaliCommandType.setBright,
        remark: 'first',
      );
      step.params.data['addr'] = 1;
      step.params.data['level'] = 200;
      final seq = CommandSequence(id: 'id1', name: 'demo', steps: [step]);
      final json = seq.toJson();
      final seq2 = CommandSequence.fromJson(json);
      expect(seq2.id, 'id1');
      expect(seq2.steps.length, 1);
      expect(seq2.steps.first.type, DaliCommandType.setBright);
      expect(seq2.steps.first.params.getInt('level'), 200);
    });
  });

  group('SequenceRepository persistence (SharedPreferences mock)', () {
    test('save -> load round trip', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SequenceRepository.instance;
      await repo.load();
      expect(repo.sequences, isEmpty);

      final step = SequenceStep(id: 's1', type: DaliCommandType.wait);
      step.params.data['ms'] = 100;
      repo.add(CommandSequence(id: 'id1', name: 'n1', steps: [step]));
      await repo.save();

      // New instance should read from prefs
      final repo2 = SequenceRepository.instance;
      await repo2.load();
      expect(repo2.sequences.length, 1);
      final loaded = repo2.sequences.first;
      expect(loaded.id, 'id1');
      expect(loaded.steps.first.type, DaliCommandType.wait);
      expect(loaded.steps.first.params.getInt('ms'), 100);
    });
  });
}
