import 'package:flutter_test/flutter_test.dart';
import 'package:dalimaster/dali/decode.dart';

void main() {
  test('DaliDecode.isQueryCmd recognises known query commands', () {
    final d = DaliDecode();
    for (final c in d.queryCmd) {
      expect(d.isQueryCmd(c), 1);
    }
    expect(d.isQueryCmd(0x05), 0); // RECALL_MAX_LEVEL is not a query
  });

  test('DaliDecode maps contain key labels', () {
    final d = DaliDecode();
    expect(d.cmd[0x00], 'OFF');
    expect(d.cmd[0x05], 'RECALL_MAX_LEVEL');
    expect(d.sCMD[0xA1], 'TERMINATE');
    expect(d.sCMD[0xC5], 'SET_DTR_2');
  });
}
