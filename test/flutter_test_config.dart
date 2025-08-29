import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global test bootstrap: initialize EasyLocalization so that String.tr() works
/// in non-widget tests without spamming missing-key warnings.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Ensure test binding and mock shared_preferences before any code runs.
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // Silence EasyLocalization logger entirely to avoid noisy warnings during unit tests.
  try {
    // Turn off all build modes for logger (per docs), and clear levels just in case.
    EasyLocalization.logger.enableBuildModes = const [];
    // ignore: invalid_use_of_visible_for_testing_member
    (EasyLocalization.logger as dynamic).enableLevels = const <dynamic>[];
  } catch (_) {}

  await testMain();
}
