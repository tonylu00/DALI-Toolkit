import 'package:flutter_test/flutter_test.dart';
import 'package:dalimaster/dali/errors.dart';

void main() {
  group('Dali errors mapping', () {
    test('map error types to i18n keys', () {
      expect(
          mapDaliErrorToMessage(const DaliBusUnavailableException()), 'dali.error.bus_unavailable');
      expect(
          mapDaliErrorToMessage(const DaliGatewayTimeoutException()), 'dali.error.gateway_timeout');
      expect(mapDaliErrorToMessage(const DaliDeviceNoResponseException()),
          'dali.error.device_no_response');
      expect(mapDaliErrorToMessage(DaliInvalidFrameException(<int>[])), 'dali.error.invalid_frame');
      expect(mapDaliErrorToMessage(const DaliInvalidGatewayFrameException()),
          'dali.error.invalid_gateway_frame');
    });

    test('daliSafe catches DaliQueryException and returns null', () async {
      final res = await daliSafe<int>(() async {
        throw const DaliGatewayTimeoutException();
      });
      expect(res, isNull);
    });

    test('daliSafe rethrows non-Dali exceptions when rethrowOthers=true', () async {
      expect(
        () => daliSafe<int>(() async {
          throw StateError('oops');
        }, rethrowOthers: true),
        throwsA(isA<StateError>()),
      );
    });
  });
}
