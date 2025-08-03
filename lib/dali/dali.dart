library dali_dart;

import 'addr.dart';
import 'base.dart';
import 'decode.dart';
import 'dt1.dart';
import 'dt8.dart';
import '/connection/manager.dart';

class Dali {
  static Dali? _instance;
  static Dali get instance {
    _instance ??= Dali();
    return _instance!;
  }
  static const int broadcast = 127;
  String name = "dali1";
  int gw = 0;
  DaliBase? base;
  DaliDecode? decode;
  DaliDT1? dt1;
  DaliDT8? dt8;
  DaliAddr? addr;
  ConnectionManager cm = ConnectionManager.instance;

  Dali({int? g, String? n}) {
    gw = g ?? gw;
    name = n ?? "dali1";
    // placeholders for any init logic
    base = DaliBase(cm);
    decode = DaliDecode();
    dt1 = DaliDT1(base!);
    dt8 = DaliDT8(base!);
    addr = DaliAddr(base!);
  }

  // Additional references or init
  void open() {
    // open COM port if needed
  }

  void close() {
    // close port if needed
  }
}