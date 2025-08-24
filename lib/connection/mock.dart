import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../dali/log.dart';
import 'connection.dart';
import 'mock_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A simulated connection for testing without real hardware.
/// - Records all sent packets to [sentPackets]
/// - Allows tests to enqueue incoming frames via [enqueueResponse]
/// - Only logs instead of performing any real I/O
class MockConnection implements Connection {
  bool _connected = false;
  String _deviceId = 'mock:0';
  final Queue<Uint8List?> _rxQueue = Queue();
  final List<Uint8List> sentPackets = [];
  void Function(Uint8List data)? _onData;

  /// Optional artificial delay for read (milliseconds).
  int readDelayMs = 0;

  /// Optional artificial delay for send (milliseconds).
  int sendDelayMs = 0;

  // --- Mock DALI bus/devices ---
  final MockDaliBus bus = MockDaliBus.create(deviceCount: 64);
  int? _lastProgramIndex; // device index selected for programming
  int? _lastVerifiedShortAddr; // for queryShortAddr
  int gatewayType = 2; // pretend 'New 485' by default
  bool autoSimulateQueries = false; // let tests control by enqueueResponse; app can enable
  // Strict selection mode: only allow program/withdraw when selH/M/L equals DUT long address
  // If [strictAutoAdjust] is true, the mock will auto-adjust selH/M/L to the chosen DUT and proceed,
  // otherwise it will no-op and log.
  bool strictSelectionMode = true;
  bool strictAutoAdjust = true;

  @override
  Future<void> connect(String address, {int port = 0}) async {
    _deviceId = address.isEmpty ? 'mock:0' : address;
    _connected = true;
    DaliLog.instance.debugLog('MockConnection.connect => $_deviceId');
    // Load optional strict flags from preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      strictSelectionMode = prefs.getBool('mockStrictMode') ?? true;
      strictAutoAdjust = prefs.getBool('mockStrictAutoAdjust') ?? true;
    } catch (_) {
      // ignore prefs errors in tests
    }
  }

  @override
  void disconnect() {
    DaliLog.instance.debugLog('MockConnection.disconnect');
    _connected = false;
    _rxQueue.clear();
  }

  @override
  Future<void> send(Uint8List data) async {
    if (sendDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: sendDelayMs));
    }
    sentPackets.add(Uint8List.fromList(data));
    DaliLog.instance.debugLog('MockConnection.send: ${data.toList()}');
    _handleWrite(data);
  }

  @override
  Future<Uint8List?> read(int length, {int timeout = 100}) async {
    if (readDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: readDelayMs));
    }
    if (_rxQueue.isEmpty) return null;
    final v = _rxQueue.removeFirst();
    readBuffer = v;
    if (v != null) {
      // If consumer registered onData handler, deliver a copy (non-blocking)
      final cb = _onData;
      if (cb != null) {
        scheduleMicrotask(() => cb(Uint8List.fromList(v)));
      }
    }
    return v;
  }

  @override
  void onReceived(void Function(Uint8List data) onData) {
    _onData = onData;
  }

  @override
  Future<void> startScan() async {
    DaliLog.instance.debugLog('MockConnection.startScan');
  }

  @override
  void stopScan() {
    DaliLog.instance.debugLog('MockConnection.stopScan');
  }

  @override
  bool isDeviceConnected() => _connected;

  @override
  void openDeviceSelection(BuildContext context) {
    // No real UI; simulate a selected device
    DaliLog.instance.debugLog('MockConnection.openDeviceSelection (noop)');
    _connected = true;
  }

  @override
  void renameDeviceDialog(BuildContext context, String currentName) {
    // No-op for mock
  }

  @override
  Uint8List? readBuffer;

  @override
  String get connectedDeviceId => _deviceId;

  @override
  String get type => 'Mock';

  // --- Test helpers ---

  void enqueueResponse(Uint8List? frame) {
    _rxQueue.add(frame);
  }

  void clear() {
    _rxQueue.clear();
    sentPackets.clear();
  }

  // --------------- Protocol simulation ---------------
  void _enqueue(List<int> bytes) {
    _rxQueue.add(Uint8List.fromList(bytes.map((e) => e & 0xFF).toList()));
  }

  void _handleWrite(Uint8List data) {
    if (data.isEmpty) return;
    final b0 = data[0];
    // Gateway type probes (see ConnectionManager.ensureGatewayType)
    if (_maybeHandleGatewayProbe(data)) return;

    if (b0 == 0x10) {
      _handleSendCmd(data); // no response required
    } else if (b0 == 0x11) {
      _handleSendExt(data); // no response required
    } else if (b0 == 0x12) {
      _handleQuery(data); // will enqueue 2-byte response
    } else if (b0 == 0x28) {
      // Legacy frames with checksum; keep minimal support for checkGatewayType path
      _handleLegacy(data);
    }
  }

  bool _maybeHandleGatewayProbe(Uint8List data) {
    // USB probe -> expect a 2-byte response later. We'll respond 0x01,0x00 (type0)
    if (listEquals(data.toList(), [0x01, 0x00, 0x00])) {
      // reply non-zero to indicate USB gateway in checkGatewayType (it treats any >0)
      _enqueue([0x01, 0x00]);
      return true;
    }
    // Legacy 485 probe (0x28,0x01,gateway,0x11,0,0,0xff) -> respond [gw,0]
    if (data.length >= 7 && data[0] == 0x28 && data[3] == 0x11 && data[6] == 0xff) {
      _enqueue([data[2], 0x00]);
      return true;
    }
    // New 485 probe (0x28,... 10 bytes) -> respond [gw,0]
    if (data.length >= 10 && data[0] == 0x28 && data[3] == 0x11 && data[9] == 0xff) {
      _enqueue([data[2], 0x00]);
      return true;
    }
    return false;
  }

  void _handleLegacy(Uint8List data) {
    // Minimal legacy handling used only by checkGatewayType retry path
    if (data.length < 6) return;
    final func = data[3];
    if (func == 0x12) {
      // send (no response)
      return;
    } else if (func == 0x13) {
      // ext (no response)
      return;
    } else if (func == 0x14) {
      final addr = data[4];
      final cmd = data[5];
      final value = _evaluateQuery(addr, cmd);
      // Build legacy 0x22 response with checksum
      final gw = 0; // use default
      final out = [0x22, 0x03, gw, value];
      final sum = (out[0] + out[1] + out[2] + out[3]) & 0xFF;
      out.add(sum);
      _enqueue(out);
    }
  }

  void _handleSendCmd(Uint8List data) {
    if (data.length < 3) return;
    final addr = data[1];
    final cmd = data[2];
    _applyCommand(addr, cmd);
  }

  void _handleSendExt(Uint8List data) {
    if (data.length < 3) return;
    final addr = data[1];
    final cmd = data[2];
    _applyExtCommand(addr, cmd);
  }

  void _handleQuery(Uint8List data) {
    if (data.length < 3) return;
    final addr = data[1];
    final cmd = data[2];
    if (!autoSimulateQueries) {
      // Do not auto respond; unit tests manage responses via enqueueResponse
      return;
    }
    // Special case: compareAddress (0xA9)
    if (addr == 0xA9) {
      if (bus.anyCompareMatch()) {
        _enqueue([255, 0x00]);
      } else {
        // signal no-response so upper layers treat as false
        _enqueue([254, 0x00]);
      }
      return;
    } // Special case: queryShortAddr (0xA1)
    if (addr == 0xA1) {
      final d = bus.getSelectedDevice();
      if (d != null && d.shortAddress != null) {
        int address = d.shortAddress!;
        _enqueue([255, address * 2 + 1]);
        return;
      } else {
        _enqueue([255, 0xFF]);
      }
    }
    final value = _evaluateQuery(addr, cmd);
    _enqueue([255, value & 0xFF]);
  }

  // ---------------- DALI behaviors ----------------
  void _applyCommand(int addr, int cmd) {
    if (addr == 0xA3) {
      // set DTR
      bus.dtr = cmd & 0xFF;
      return;
    }
    if (addr == 0xC3) {
      bus.dtr1 = cmd & 0xFF;
      return;
    }
    if (addr == 0xC5) {
      bus.dtr2 = cmd & 0xFF;
      return;
    }

    // Special addressing commands (t:1)
    if (addr == 0xB1) {
      bus.selH = cmd & 0xFF; // queryAddressH
      return;
    }
    if (addr == 0xB3) {
      bus.selM = cmd & 0xFF; // queryAddressM
      return;
    }
    if (addr == 0xB5) {
      bus.selL = cmd & 0xFF; // queryAddressL
      return;
    }
    if (addr == 0xB7) {
      // programShortAddr, cmd is encoded short address (2*n+1)
      final shortAddr = (cmd - 1) ~/ 2;
      // Candidate according to current selection window (max < sel)
      final candidateIdx = bus.pickDeviceIndexForProgramming();
      if (candidateIdx == null) return;
      int idxToProgram = candidateIdx;
      if (strictSelectionMode) {
        // Find exact match by current selection registers
        final exactIdx = bus.indexByLongAddr(bus.selH, bus.selM, bus.selL,
            requireUnaddressed: true, requireNotIsolated: true);
        if (exactIdx == null) {
          DaliLog.instance.debugLog(
              'Mock: strict programShortAddr mismatch sel=(${bus.selH},${bus.selM},${bus.selL}) vs target=(${bus.devices[candidateIdx].randH},${bus.devices[candidateIdx].randM},${bus.devices[candidateIdx].randL})');
          if (strictAutoAdjust) {
            // Auto align selection to the target DUT to satisfy strict equality
            final d = bus.devices[candidateIdx];
            bus.selH = d.randH;
            bus.selM = d.randM;
            bus.selL = d.randL;
            idxToProgram = candidateIdx;
            assert(() {
              final ok = bus.selH == d.randH && bus.selM == d.randM && bus.selL == d.randL;
              return ok;
            }());
          } else {
            // Do not proceed when strict is enabled and auto-adjust is off
            return;
          }
        } else {
          idxToProgram = exactIdx;
        }
      }
      bus.devices[idxToProgram].shortAddress = shortAddr;
      _lastVerifiedShortAddr = shortAddr;
      _lastProgramIndex = idxToProgram; // remember for withdraw()
      return;
    }
    if (addr == 0xAB) {
      // withdraw: isolate last programmed device
      if (_lastProgramIndex != null) {
        final i = _lastProgramIndex!;
        if (strictSelectionMode) {
          final d = bus.devices[i];
          final equal = (bus.selH == d.randH && bus.selM == d.randM && bus.selL == d.randL);
          if (!equal) {
            DaliLog.instance.debugLog(
                'Mock: strict withdraw mismatch sel=(${bus.selH},${bus.selM},${bus.selL}) vs last=(${d.randH},${d.randM},${d.randL})');
            if (strictAutoAdjust) {
              // Align selection to the last programmed DUT
              bus.selH = d.randH;
              bus.selM = d.randM;
              bus.selL = d.randL;
              assert(() {
                final ok = bus.selH == d.randH && bus.selM == d.randM && bus.selL == d.randL;
                return ok;
              }());
            } else {
              return; // Do not withdraw when strict mismatch and no auto-adjust
            }
          }
        }
        bus.devices[i].isolated = true;
      }
      return;
    }
    if (addr == 0xAD) {
      // cancel: unisolate all
      for (final d in bus.devices) {
        d.isolated = false;
      }
      return;
    }

    // Direct arc power control & address domain
    if ((addr & 0x01) == 0) {
      // even addr: direct arc. It can be broadcast/group/individual
      if (addr == 0xFE) {
        // broadcast direct arc
        for (final d in bus.devices) {
          if (d.shortAddress != null) d.brightness = cmd.clamp(0, 254);
        }
      } else if (addr >= 0x80 && addr <= 0xBE) {
        // group direct arc: 0x80 + 2*g
        final g = (addr - 0x80) ~/ 2;
        for (final d in bus.devices) {
          if (d.shortAddress != null && (d.groupBits & (1 << g)) != 0) {
            d.brightness = cmd.clamp(0, 254);
          }
        }
      } else {
        // individual direct arc
        final saInd = addr ~/ 2;
        _forEachTarget(saInd, (d) => d.brightness = cmd.clamp(0, 254));
      }
      return;
    }

    // Odd addr (2n+1): broadcast=0xFF, group=0x81..0xBF, individual otherwise
    int? targetSa; // null=broadcast, -1=group, >=0 individual SA
    if (addr == 0xFF)
      targetSa = null;
    else if (addr >= 0x81 && addr <= 0xBF)
      targetSa = -1;
    else
      targetSa = (addr - 1) ~/ 2;

    void applyToTargets(void Function(MockDaliDevice d) fn) {
      if (targetSa == null) {
        for (final d in bus.devices) {
          if (d.shortAddress != null) fn(d);
        }
      } else if (targetSa == -1) {
        final g = (addr - 0x81) ~/ 2;
        for (final d in bus.devices) {
          if (d.shortAddress != null && (d.groupBits & (1 << g)) != 0) fn(d);
        }
      } else {
        _forEachTarget(targetSa, fn);
      }
    }

    switch (cmd) {
      case 0x00: // OFF
        applyToTargets((d) => d.brightness = 0);
        break;
      case 0x05: // RECALL MAX LEVEL
        applyToTargets((d) => d.brightness = d.maxLevel);
        break;
      case 0x06: // RECALL MIN LEVEL
        applyToTargets((d) => d.brightness = d.minLevel);
        break;
      default:
        // Scene Recall 0x10..0x1F
        if (cmd >= 0x10 && cmd <= 0x1F) {
          final scene = cmd - 0x10;
          applyToTargets((d) => d.brightness = d.scenes[scene]);
        }
        break;
    }
  }

  void _applyExtCommand(int addr, int cmd) {
    // Extended commands. For short address: addr = 2*sa+1
    if (addr == 0xA7) {
      // randomise() => assign random long addresses for all unaddressed & not isolated
      final r = Random(479460242);
      for (final d in bus.devices) {
        if (d.shortAddress == null && !d.isolated) {
          d.randH = r.nextInt(256);
          d.randM = r.nextInt(256);
          d.randL = r.nextInt(256);
        }
      }
      return;
    }
    if (addr == 0xA5) {
      // initialise(all or unaddressed)
      // If cmd==0x00 => all; 0xFF => only unaddressed. Here no special state needed.
      return;
    }

    // store DTR as addr/scene/levels when targeted
    if ((addr & 0x01) == 1 && addr != 0xA7 && addr != 0xA5) {
      final sa = (addr - 1) ~/ 2;
      final d = bus.deviceByShortAddr(sa);
      if (d == null) return;
      if (cmd == 0x80) {
        // store DTR as short address; DTR=0xFF means remove short address
        final newAddr = bus.dtr & 0xFF;
        if (newAddr == 0xFF) {
          d.shortAddress = null;
          d.isolated = false; // removing addr also removes isolation
        } else {
          d.shortAddress = (newAddr - 1) ~/ 2;
        }
        return;
      }
      if (cmd >= 0x40 && cmd <= 0x4F) {
        // store scene brightness: cmd - 0x40 => scene index
        final scene = cmd - 0x40;
        if (scene >= 0 && scene < 16) d.scenes[scene] = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2E) {
        d.fadeTime = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2F) {
        d.fadeRate = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2D) {
        d.powerOnLevel = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2C) {
        d.systemFailureLevel = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2B) {
        d.minLevel = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0x2A) {
        d.maxLevel = bus.dtr & 0xFF;
        return;
      }
      if (cmd == 0xF2) {
        // colour temp limits store: not modeled, ignore
        return;
      }
      if (cmd == 0xE7) {
        // set DTR/DTR1 as mirek
        d.mirek = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        d.activeColorMode = 'ct';
        d.colorType = 0x20; // color temp
        return;
      }
      if (cmd == 0xE0) {
        final x = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        d.xyX = x;
        d.activeColorMode = 'xy';
        d.colorType = 0x10; // xy
        return;
      }
      if (cmd == 0xE1) {
        final y = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        d.xyY = y;
        d.activeColorMode = 'xy';
        d.colorType = 0x10;
        return;
      }
      if (cmd == 0xE2) {
        // RGB raw -> 留给上层做 rgb->xy；这里也存储原始 RGBWAF 通道（DTR=r, DTR1=g, DTR2=b）
        // 额外通道 W/A/F 暂保留为 0，可扩展自定义指令映射。
        d.rgbwafChannels[0] = bus.dtr & 0xFF;
        d.rgbwafChannels[1] = bus.dtr1 & 0xFF;
        d.rgbwafChannels[2] = bus.dtr2 & 0xFF;
        d.activeColorMode = 'xy';
        d.colorType = 0x10;
        return;
      }
      if (cmd >= 0x60 && cmd <= 0x6F) {
        // add to group i
        final g = cmd - 0x60;
        d.groupBits |= (1 << g);
        return;
      }
      if (cmd >= 0x70 && cmd <= 0x7F) {
        // remove from group i
        final g = cmd - 0x70;
        d.groupBits &= ~(1 << g);
        return;
      }
    }
  }

  int _evaluateQuery(int addr, int cmd) {
    // Selection/compare path
    if (addr == 0xA9) {
      // compareAddress(): return any device matched => >=0; we return 0 for ok
      return bus.anyCompareMatch() ? 0 : 0; // value doesn't matter for 0x12 flow
    }
    if (addr == 0xBB) {
      // queryShortAddr(): return (2*short+1)+1? In base, queryRawNew expects [255, value]
      // The base then maps ret1-1 => /2
      final sa = _lastVerifiedShortAddr ?? 0;
      return (2 * sa + 1) + 1; // mimic base expectation
    }
    if (addr == 0xB9) {
      // verifyShortAddr: value ignored, respond OK
      return 0;
    }

    // Address registers queries
    if (addr == 0xC2) return bus.selH & 0xFF;
    if (addr == 0xC3) return bus.selM & 0xFF;
    if (addr == 0xC4) return bus.selL & 0xFF;

    // Short address/command space
    if ((addr & 0x01) == 1) {
      final sa = (addr - 1) ~/ 2;
      final d = bus.deviceByShortAddr(sa);
      // If no device present => mimic 254 (no response) by returning 0, but query layer expects a protocol signal.
      if (d == null) return 0;
      switch (cmd) {
        case 0x90: // DaliStatus byte
          int st = 0;
          st |= 0x01; // controlGearPresent
          if (d.lampFailureFlag) st |= 0x02;
          if ((d.brightness > 0)) st |= 0x04; // lampPowerOn (approx by brightness)
          if (d.limitErrorFlag) st |= 0x08;
          if (d.fadingCompletedFlag) st |= 0x10;
          if (d.resetStateFlag) st |= 0x20;
          if (d.shortAddress == null) st |= 0x40; // missingShortAddress
          if (d.psFaultFlag) st |= 0x80;
          return st & 0xFF;
        case 0x91: // online
          return 255;
        case 0x92: // lampFailure
          return d.lampFailureFlag ? 255 : 0;
        case 0x93: // lampPowerOn
          return (d.brightness > 0) ? 255 : 0;
        case 0x94: // limitError
          return d.limitErrorFlag ? 255 : 0;
        case 0x95: // resetState
          return d.resetStateFlag ? 255 : 0;
        case 0x96: // missingShortAddress
          return (d.shortAddress == null) ? 255 : 0;
        case 0xA0: // bright
          return d.brightness;
        case 0x99: // device type
          return d.deviceType;
        case 0x9A: // ext type
          return d.extType;
        case 0x97: // version
          return d.version;
        case 0xA1:
          return d.powerOnLevel;
        case 0xA2:
          return d.systemFailureLevel;
        case 0xA3:
          return d.minLevel;
        case 0xA4:
          return d.maxLevel;
        case 0xA5:
          return d.physicalMinLevel;
        case 0xA6:
          return d.fadeTime;
        case 0xA7:
          return d.fadeRate;
        case 0xC1:
          return (d.groupBits >> 8) & 0xFF;
        case 0xC0:
          return d.groupBits & 0xFF;
        case 0xF9:
          // DALI DT8 getColorType
          return d.colorType;
        case 0xF8:
          // DALI DT8 getColorStatus
          int status = 0;
          // out-of-range checks
          final xyOut =
              (d.xyX < d.xyMinX || d.xyX > d.xyMaxX || d.xyY < d.xyMinY || d.xyY > d.xyMaxY);
          final ctOut = (d.mirek < d.mirekMin || d.mirek > d.mirekMax);
          if (xyOut) status |= 0x01; // xyOutOfRange
          if (ctOut) status |= 0x02; // ctOutOfRange
          // active flags
          if (d.activeColorMode == 'xy') status |= 0x10; // xyActive
          if (d.activeColorMode == 'ct') status |= 0x20; // ctActive
          return status;
        case 0xFA:
          // queryColourValue: depends on DTR selector (0: x, 1: y, 2: ct; 128/130 for min/max per dt8.dart)
          final sel = bus.dtr & 0xFF;
          if (sel == 0) {
            // X low byte; but dt8.dart随后通过 getDTR/getDTR1 读取，我们返回触发后续读取
            // 这里直接返回 0 即可，真正数据由后续 getDTR/1 提供
            return 0;
          } else if (sel == 1) {
            return 0;
          } else if (sel == 2) {
            return 0;
          } else if (sel == 128) {
            return 0; // min ct requires getDTR/getDTR1
          } else if (sel == 130) {
            return 0; // max ct requires getDTR/getDTR1
          }
          return 0;
        case 0x98:
          // getDTR on device: map according to last selector used in dt8.dart
          // If selector 0/1 -> X/Y low; 2 -> mirek low; 128/130 -> min/max mirek low
          switch (bus.dtr & 0xFF) {
            case 0:
              return d.xyX & 0xFF;
            case 1:
              return d.xyY & 0xFF;
            case 2:
              return d.mirek & 0xFF;
            case 128:
              return d.mirekMin & 0xFF;
            case 130:
              return d.mirekMax & 0xFF;
            default:
              return bus.dtr & 0xFF;
          }
        case 0x9C:
          switch (bus.dtr & 0xFF) {
            case 0:
              return (d.xyX >> 8) & 0xFF;
            case 1:
              return (d.xyY >> 8) & 0xFF;
            case 2:
              return (d.mirek >> 8) & 0xFF;
            case 128:
              return (d.mirekMin >> 8) & 0xFF;
            case 130:
              return (d.mirekMax >> 8) & 0xFF;
            default:
              return bus.dtr1 & 0xFF;
          }
        case 0x9D:
          return bus.dtr2 & 0xFF;
        default:
          if (cmd >= 0xB0 && cmd <= 0xBF) {
            final sc = cmd - 0xB0;
            return d.scenes[sc];
          }
          return 0;
      }
    }

    // Direct arc power control query space is rare; default 0
    return 0;
  }

  void _forEachTarget(int shortAddr, void Function(MockDaliDevice d) fn) {
    for (final d in bus.devices) {
      if (d.shortAddress == shortAddr) fn(d);
    }
  }

  // --------- Public teaching/testing helpers ---------
  Future<String> exportProjectJson({bool pretty = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = prefs.getString('anonymousId') ?? '';
    final projectName = prefs.getString('projectName') ?? 'Untitled Project';
    final meta = {
      'generatedAt': DateTime.now().toIso8601String(),
      'projectName': projectName,
      'uuid': uuid,
      'connection': 'Mock',
    };
    return bus.exportJson(pretty: pretty, meta: meta);
  }

  // Configure DT8 gamut for all devices (teaching purpose)
  void setGlobalGamut({int xMin = 0, int xMax = 65535, int yMin = 0, int yMax = 65535}) {
    for (final d in bus.devices) {
      d.xyMinX = xMin;
      d.xyMaxX = xMax;
      d.xyMinY = yMin;
      d.xyMaxY = yMax;
    }
  }
}
