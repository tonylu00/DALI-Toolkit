import 'dart:typed_data';

import 'package:dalimaster/connection/manager.dart';
import 'package:dalimaster/connection/mock.dart';
import 'package:dalimaster/dali/base.dart';
import 'package:dalimaster/dali/comm.dart';
import 'package:dalimaster/dali/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await ConnectionManager.instance.useMock();
  });

  group('Mock connection basic', () {
    test('start/stop scan no-op', () async {
      final conn = ConnectionManager.instance.connection as MockConnection;
      await conn.connect('mock');
      await conn.startScan();
      conn.stopScan();
      expect(conn.isDeviceConnected(), isTrue);
    });
  });

  group('Command assembly (isSingle/new)', () {
    test('sendRawNew builds [0x10, addr, cmd]', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();

      await comm.sendRawNew(0x23, 0xA5);
      expect(conn.sentPackets, isNotEmpty);
      expect(conn.sentPackets.last, Uint8List.fromList([0x10, 0x23, 0xA5]));
    });

    test('sendExtRawNew builds [0x11, addr, cmd]', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();

      await comm.sendExtRawNew(0x7F, 0x2E);
      expect(conn.sentPackets.last, Uint8List.fromList([0x11, 0x7F, 0x2E]));
    });

    test('send() uses DEC->(2n+1) mapping', () async {
      final cm = ConnectionManager.instance;
      final base = DaliBase(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();

      await base.send(1, 0x05);
      // addr => 1*2+1 = 3
      expect(conn.sentPackets.last, Uint8List.fromList([0x10, 0x03, 0x05]));
    });
  });

  group('Robustness on abnormal responses', () {
    test('queryRawNew success 255,x', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1; // speed up test

      conn.enqueueResponse(Uint8List.fromList([255, 0x42]));
      final v = await comm.queryRawNew(0x20, 0x91);
      expect(v, 0x42);
    });

    test('queryRawNew device no response 254', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1;

      conn.enqueueResponse(Uint8List.fromList([254, 0x00]));
      expect(() => comm.queryRawNew(0x01, 0x90), throwsA(isA<DaliDeviceNoResponseException>()));
    });

    test('queryRawNew tolerates one invalid frame (253) then success', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1;
      comm.invalidFrameTolerance = 1;

      conn.enqueueResponse(Uint8List.fromList([253, 0x00]));
      conn.enqueueResponse(Uint8List.fromList([255, 0x55]));

      final v = await comm.queryRawNew(0x02, 0x90);
      expect(v, 0x55);
    });

    test('queryRawNew exceeds tolerance -> InvalidFrameException', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1;
      comm.invalidFrameTolerance = 1;

      conn.enqueueResponse(Uint8List.fromList([253, 0x00]));
      conn.enqueueResponse(Uint8List.fromList([253, 0x00]));

      expect(() => comm.queryRawNew(0x03, 0x90), throwsA(isA<DaliInvalidFrameException>()));
    });

    test('queryRawNew unknown gateway frame throws', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1;

      conn.enqueueResponse(Uint8List.fromList([250, 0x01]));
      expect(() => comm.queryRawNew(0x04, 0x90), throwsA(isA<DaliInvalidGatewayFrameException>()));
    });

    test('queryRawNew timeout with no data', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();
      comm.queryDelays = 1;

      // No enqueued responses -> will retry and then timeout
      expect(() => comm.queryRawNew(0x05, 0x90), throwsA(isA<DaliGatewayTimeoutException>()));
    });
  });

  group('Out-of-range byte handling', () {
    test('negative address is masked to 8-bit', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();

      await comm.sendRawNew(-5, 0x05); // -5 & 0xFF == 251
      expect(conn.sentPackets.last, Uint8List.fromList([0x10, 251, 0x05]));
    });

    test('cmd > 255 does not crash (ignored by guard)', () async {
      final cm = ConnectionManager.instance;
      final comm = DaliComm(cm);
      final conn = cm.connection as MockConnection;
      conn.clear();

      await comm.sendRawNew(0x01, 300); // >255 -> should be ignored/logged, no packet appended
      expect(conn.sentPackets, isEmpty);
    });
  });
}
