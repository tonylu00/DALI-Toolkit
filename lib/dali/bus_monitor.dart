import 'dart:async';
import 'decode.dart';

/// Bus frame directions
enum BusDir { front, back }

/// Raw bus frame captured near gateway API level.
class BusFrame {
  final BusDir dir;
  final int proto; // 0x10 send, 0x11 ext, 0x12 query; 0xFF response
  final int b1;
  final int b2;
  final DateTime ts;
  BusFrame(
      {required this.dir, required this.proto, required this.b1, required this.b2, DateTime? ts})
      : ts = ts ?? DateTime.now();
}

/// Singleton monitor that decodes frames to lines and streams to UI.
class BusMonitor {
  static BusMonitor? _inst;
  static BusMonitor get I => _inst ??= BusMonitor._();
  BusMonitor._();

  final _rawCtrl = StreamController<BusFrame>.broadcast();
  final _decodedCtrl = StreamController<DecodedRecord>.broadcast();
  final decoder = DaliDecode();
  // Keep decoded history in memory until app exit
  final List<DecodedRecord> _records = <DecodedRecord>[];
  List<DecodedRecord> get records => List.unmodifiable(_records);
  // Persist UI state across navigations
  double lastScrollOffset = 0.0;
  bool lastAutoScroll = true;

  Stream<BusFrame> get rawStream => _rawCtrl.stream;
  Stream<DecodedRecord> get decodedStream => _decodedCtrl.stream;

  void setResponseWindowMs(int ms) {
    decoder.responseWindowMs = ms;
  }

  void emitFront(int proto, int addr, int cmd) {
    final f = BusFrame(dir: BusDir.front, proto: proto, b1: addr & 0xFF, b2: cmd & 0xFF);
    _rawCtrl.add(f);
    final rec = decoder.decode(addr & 0xFF, cmd & 0xFF, proto: proto);
    _records.add(rec);
    _decodedCtrl.add(rec);
  }

  void emitBack(int value, {int prefix = 0xFF}) {
    final f = BusFrame(dir: BusDir.back, proto: 0xFF, b1: prefix & 0xFF, b2: value & 0xFF);
    _rawCtrl.add(f);
    final rec = decoder.decodeCmdResponse(value & 0xFF, gwPrefix: prefix & 0xFF);
    _records.add(rec);
    _decodedCtrl.add(rec);
  }

  void clear() {
    _records.clear();
  }

  void dispose() {
    _rawCtrl.close();
    _decodedCtrl.close();
  }
}
