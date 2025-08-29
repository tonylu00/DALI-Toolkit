import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../dali/log.dart';
import 'connection.dart';
import 'manager.dart';
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
  bool strictSelectionMode = false;
  bool strictAutoAdjust = true;

  @override
  Future<void> connect(String address, {int port = 0}) async {
    _deviceId = address.isEmpty ? 'mock:0' : address;
    _connected = true;
    DaliLog.instance.debugLog('MockConnection.connect => $_deviceId');
    // Load optional strict flags from preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      strictSelectionMode = prefs.getBool('mockStrictMode') ?? false;
      strictAutoAdjust = prefs.getBool('mockStrictAutoAdjust') ?? true;
      autoSimulateQueries = prefs.getBool('mockAutoSimulateQueries') ?? true;
    } catch (_) {
      // ignore prefs errors in tests
    }
    ConnectionManager.instance.ensureGatewayType().then((_) {
      ConnectionManager.instance.updateConnectionStatus(true);
    });
  }

  @override
  void disconnect() {
    DaliLog.instance.debugLog('MockConnection.disconnect');
    _connected = false;
    _rxQueue.clear();
    try {
      ConnectionManager.instance.updateConnectionStatus(false);
    } catch (_) {}
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
    final int start = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      if (readDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: readDelayMs));
      }
      if (_rxQueue.isNotEmpty) {
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
      final elapsed = DateTime.now().millisecondsSinceEpoch - start;
      if (elapsed >= timeout) return null;
      final wait = timeout - elapsed;
      await Future.delayed(Duration(milliseconds: wait > 10 ? 10 : (wait > 0 ? wait : 1)));
    }
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
    // No real UI; directly connect with default mock device id
    DaliLog.instance.debugLog('MockConnection.openDeviceSelection -> connect(mock:0)');
    // Kick off the same flow as connect() to keep behavior consistent
    // Ignore the returned future intentionally
    // Use default deviceId 'mock:0'
    // Note: connect() will set prefs-based strict flags and notify manager
    // (ensureGatewayType + updateConnectionStatus)
    // This keeps the UI state in sync with other connection types.
    //
    // Intentionally not awaiting to keep the call site sync-compatible.
    // Any errors are logged inside connect().
    // ignore: discarded_futures
    connect('mock:0');
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
    }
    // Special case: queryShortAddr (0xA1)
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
    // Broadcast and group addressed queries cause bus collision => respond 253,0
    // Exclude pseudo addresses used by addressing procedure (e.g., 0xB9, 0xBB)
    if (addr == 0xFF || (addr >= 0x81 && addr <= 0xBF && addr != 0xB9 && addr != 0xBB)) {
      _enqueue([253, 0x00]);
      return;
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
          d.brightness = cmd.clamp(0, 254);
        }
      } else if (addr >= 0x80 && addr <= 0xBE) {
        // group direct arc: 0x80 + 2*g
        final g = (addr - 0x80) ~/ 2;
        for (final d in bus.devices) {
          if ((d.groupBits & (1 << g)) != 0) {
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
    if (addr == 0xFF) {
      targetSa = null;
    } else if (addr >= 0x81 && addr <= 0xBF) {
      targetSa = -1;
    } else {
      targetSa = (addr - 1) ~/ 2;
    }

    void applyToTargets(void Function(MockDaliDevice d) fn) {
      if (targetSa == null) {
        // Broadcast to ALL devices, regardless of short address
        for (final d in bus.devices) {
          fn(d);
        }
      } else if (targetSa == -1) {
        final g = (addr - 0x81) ~/ 2;
        for (final d in bus.devices) {
          if ((d.groupBits & (1 << g)) != 0) fn(d);
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

    // dtSelect for DT8 (0xC1, t:1, value in DTR0)
    if (addr == 0xC1) {
      // For simplicity, we don't need to persist selected DT in mock
      return;
    }

    // store DTR as addr/scene/levels when targeted
    if ((addr & 0x01) == 1 && addr != 0xA7 && addr != 0xA5) {
      // Determine targets: broadcast (0xFF), group (0x81..0xBF), or individual (2*sa+1)
      Iterable<MockDaliDevice> targets = const [];
      if (addr == 0xFF) {
        // Broadcast to ALL devices, regardless of short address
        targets = bus.devices;
      } else if (addr >= 0x81 && addr <= 0xBF) {
        final g = (addr - 0x81) ~/ 2;
        // Group addressing applies regardless of short address
        targets = bus.devices.where((d) => (d.groupBits & (1 << g)) != 0);
      } else {
        final sa = (addr - 1) ~/ 2;
        final d = bus.deviceByShortAddr(sa);
        if (d == null) return;
        targets = [d];
      }

      void forEachTarget(void Function(MockDaliDevice d) fn) {
        for (final t in targets) {
          fn(t);
        }
      }

      if (cmd == 0x80) {
        // store DTR as short address; DTR=0xFF means remove short address
        final newAddr = bus.dtr & 0xFF;
        forEachTarget((d) {
          if (newAddr == 0xFF) {
            d.shortAddress = null;
            d.isolated = false; // removing addr also removes isolation
          } else {
            d.shortAddress = (newAddr - 1) ~/ 2;
          }
        });
        return;
      }
      if (cmd >= 0x40 && cmd <= 0x4F) {
        // store scene brightness: cmd - 0x40 => scene index
        final scene = cmd - 0x40;
        if (scene >= 0 && scene < 16) {
          final v = bus.dtr & 0xFF;
          forEachTarget((d) => d.scenes[scene] = v);
        }
        return;
      }
      if (cmd == 0x2E) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.fadeTime = v);
        return;
      }
      if (cmd == 0x2F) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.fadeRate = v);
        return;
      }
      if (cmd == 0x2D) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.powerOnLevel = v);
        return;
      }
      if (cmd == 0x2C) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.systemFailureLevel = v);
        return;
      }
      if (cmd == 0x2B) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.minLevel = v);
        return;
      }
      if (cmd == 0x2A) {
        final v = bus.dtr & 0xFF;
        forEachTarget((d) => d.maxLevel = v);
        return;
      }
      if (cmd == 0xF2) {
        // colour temp limits store: not modeled, ignore
        return;
      }
      if (cmd == 0xE7) {
        // set DTR/DTR1 as mirek
        final mirek = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        forEachTarget((d) {
          d.mirek = mirek;
          d.activeColorMode = 'ct';
          d.colorType = 0x20; // color temp
        });
        return;
      }
      if (cmd == 0xE0) {
        final x = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        forEachTarget((d) {
          d.xyX = x;
          d.activeColorMode = 'xy';
          d.colorType = 0x10; // xy
        });
        return;
      }
      if (cmd == 0xE1) {
        final y = (bus.dtr1 & 0xFF) * 256 + (bus.dtr & 0xFF);
        forEachTarget((d) {
          d.xyY = y;
          d.activeColorMode = 'xy';
          d.colorType = 0x10;
        });
        return;
      }
      if (cmd == 0xE2) {
        // RGB raw -> 留给上层做 rgb->xy；这里也存储原始 RGBWAF 通道（DTR=r, DTR1=g, DTR2=b）
        // 额外通道 W/A/F 暂保留为 0，可扩展自定义指令映射。
        final r = bus.dtr & 0xFF;
        final g = bus.dtr1 & 0xFF;
        final b = bus.dtr2 & 0xFF;
        forEachTarget((d) {
          d.rgbwafChannels[0] = r;
          d.rgbwafChannels[1] = g;
          d.rgbwafChannels[2] = b;
          d.activeColorMode = 'xy';
          d.colorType = 0x10;
        });
        return;
      }
      if (cmd == 0xFA) {
        // QUERY COLOUR VALUE as an extended command that writes back into DTR/DTR1
        final sel = bus.dtr & 0xFF;
        void set16(int value) {
          bus.dtr = value & 0xFF;
          bus.dtr1 = (value >> 8) & 0xFF;
        }

        forEachTarget((d) {
          switch (sel) {
            case 0:
              set16(d.xyX);
              break;
            case 1:
              set16(d.xyY);
              break;
            case 2:
              set16(d.mirek);
              break;
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
              {
                final n = sel - 3;
                final v = (n >= 0 && n < d.primaryN.length) ? d.primaryN[n] : 255;
                set16(v);
                break;
              }
            case 9:
              set16(d.rgbwafChannels[0]);
              break;
            case 10:
              set16(d.rgbwafChannels[1]);
              break;
            case 11:
              set16(d.rgbwafChannels[2]);
              break;
            case 12:
              set16(d.rgbwafChannels[3]);
              break;
            case 13:
              set16(d.rgbwafChannels[4]);
              break;
            case 14:
              set16(d.rgbwafChannels[5]);
              break;
            case 15:
              set16(0);
              break;
            case 64:
            case 67:
            case 70:
            case 73:
            case 76:
            case 79:
              {
                final n = (sel - 64) ~/ 3;
                final x = (10000 + n * 1000).clamp(0, 65535);
                set16(x);
                break;
              }
            case 65:
            case 68:
            case 71:
            case 74:
            case 77:
            case 80:
              {
                final n = (sel - 65) ~/ 3;
                final y = (12000 + n * 1000).clamp(0, 65535);
                set16(y);
                break;
              }
            case 66:
            case 69:
            case 72:
            case 75:
            case 78:
            case 81:
              {
                final n = (sel - 66) ~/ 3;
                final ty = (n + 1) & 0xFF;
                set16(ty);
                break;
              }
            case 82:
              set16(3);
              break;
            case 128:
              set16(d.mirekMin);
              break;
            case 129:
              set16(d.mirekMin);
              break;
            case 130:
              set16(d.mirekMax);
              break;
            case 131:
              set16(d.mirekMax);
              break;
            case 192:
              set16(d.tmpX);
              break;
            case 193:
              set16(d.tmpY);
              break;
            case 194:
              set16(d.tmpMirek);
              break;
            case 195:
            case 196:
            case 197:
            case 198:
            case 199:
            case 200:
              {
                final n = sel - 195;
                final v = (n >= 0 && n < d.tmpPrimary.length) ? d.tmpPrimary[n] : 255;
                set16(v);
                break;
              }
            case 201:
              set16(d.tmpRGBWAF[0]);
              break;
            case 202:
              set16(d.tmpRGBWAF[1]);
              break;
            case 203:
              set16(d.tmpRGBWAF[2]);
              break;
            case 204:
              set16(d.tmpRGBWAF[3]);
              break;
            case 205:
              set16(d.tmpRGBWAF[4]);
              break;
            case 206:
              set16(d.tmpRGBWAF[5]);
              break;
            case 207:
              set16(0);
              break;
            case 208:
              set16(d.tmpColourType);
              break;
            case 224:
              set16(d.xyX);
              break;
            case 225:
              set16(d.xyY);
              break;
            case 226:
              set16(d.mirek);
              break;
            case 227:
            case 228:
            case 229:
            case 230:
            case 231:
            case 232:
              {
                final n = sel - 227;
                final v = (n >= 0 && n < d.primaryN.length) ? d.primaryN[n] : 255;
                set16(v);
                break;
              }
            case 233:
              set16(d.rgbwafChannels[0]);
              break;
            case 234:
              set16(d.rgbwafChannels[1]);
              break;
            case 235:
              set16(d.rgbwafChannels[2]);
              break;
            case 236:
              set16(d.rgbwafChannels[3]);
              break;
            case 237:
              set16(d.rgbwafChannels[4]);
              break;
            case 238:
              set16(d.rgbwafChannels[5]);
              break;
            case 239:
              set16(0);
              break;
            case 240:
              set16(d.colorType & 0xFF);
              break;
            default:
              break;
          }
        });
        return;
      }
      if (cmd == 0xEE) {
        // copyReportColourToTemp: take a snapshot from current report values
        forEachTarget((d) {
          d.tmpX = d.xyX;
          d.tmpY = d.xyY;
          d.tmpMirek = d.mirek;
          for (var i = 0; i < d.tmpRGBWAF.length && i < d.rgbwafChannels.length; i++) {
            d.tmpRGBWAF[i] = d.rgbwafChannels[i];
          }
          for (var i = 0; i < d.tmpPrimary.length && i < d.primaryN.length; i++) {
            d.tmpPrimary[i] = d.primaryN[i];
          }
          // Map active mode to colour type code
          switch (d.activeColorMode) {
            case 'xy':
              d.tmpColourType = 0x10;
              break;
            case 'ct':
              d.tmpColourType = 0x20;
              break;
            case 'rgb':
              d.tmpColourType = 0x80;
              break;
            default:
              d.tmpColourType = d.colorType & 0xFF;
          }
        });
        return;
      }
      if (cmd >= 0x60 && cmd <= 0x6F) {
        // add to group i
        final g = cmd - 0x60;
        forEachTarget((d) => d.groupBits |= (1 << g));
        return;
      }
      if (cmd >= 0x70 && cmd <= 0x7F) {
        // remove from group i
        final g = cmd - 0x70;
        forEachTarget((d) => d.groupBits &= ~(1 << g));
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
      return 2 * sa + 1; // mimic base expectation
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
          // DALI DT8 Colour Type Features (bit0 xy, bit1 ct, bit2..4 primaries count, bit5..7 rgbwaf channels)
          int features = 0;
          // For our mock device, enable xy+ct, 3 primaries, 3 rgb channels by default
          features |= 0x01; // xy capable
          features |= 0x02; // ct capable
          // number of primaries (use non-zero if primaryN has any meaningful values)
          final primaries = d.primaryN.any((v) => v != 0) ? 3 : 0;
          features |= (primaries.clamp(0, 6) & 0x07) << 2;
          // rgbwaf channels (infer from non-zero entries; default 3 for RGB)
          int ch = d.rgbwafChannels.where((v) => v != 0).length;
          if (ch == 0) ch = 3; // default RGB
          features |= (ch.clamp(0, 6) & 0x07) << 5;
          return features & 0xFF;
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
          {
            // QUERY COLOUR VALUE; Answer placed in DTR/DTR1 depending on selector
            final sel = bus.dtr & 0xFF;
            // Helper closures
            void set16(int value) {
              bus.dtr = value & 0xFF;
              bus.dtr1 = (value >> 8) & 0xFF;
            }

            switch (sel) {
              // Active-related 0..15
              case 0:
                set16(d.xyX);
                break;
              case 1:
                set16(d.xyY);
                break;
              case 2:
                set16(d.mirek);
                break;
              case 3:
              case 4:
              case 5:
              case 6:
              case 7:
              case 8:
                {
                  final n = sel - 3;
                  final v = (n >= 0 && n < d.primaryN.length) ? d.primaryN[n] : 255; // MASK
                  set16(v);
                  break;
                }
              case 9:
                set16(d.rgbwafChannels[0]);
                break;
              case 10:
                set16(d.rgbwafChannels[1]);
                break;
              case 11:
                set16(d.rgbwafChannels[2]);
                break;
              case 12:
                set16(d.rgbwafChannels[3]);
                break;
              case 13:
                set16(d.rgbwafChannels[4]);
                break;
              case 14:
                set16(d.rgbwafChannels[5]);
                break;
              case 15:
                set16(0); // RGBWAF CONTROL: keep 0
                break;

              // Primary N info 64..82: return raw 16-bit for x/y (simulate 16-bit), TY & NUMBER single byte in low
              case 64:
              case 67:
              case 70:
              case 73:
              case 76:
              case 79:
                {
                  final n = (sel - 64) ~/ 3;
                  final x = (10000 + n * 1000).clamp(0, 65535);
                  set16(x);
                  break;
                }
              case 65:
              case 68:
              case 71:
              case 74:
              case 77:
              case 80:
                {
                  final n = (sel - 65) ~/ 3;
                  final y = (12000 + n * 1000).clamp(0, 65535);
                  set16(y);
                  break;
                }
              case 66:
              case 69:
              case 72:
              case 75:
              case 78:
              case 81:
                {
                  final n = (sel - 66) ~/ 3;
                  final ty = (n + 1) & 0xFF;
                  set16(ty);
                  break;
                }
              case 82:
                set16(3); // NUMBER OF PRIMARIES -> say 3
                break;

              // CT min/physical min/max/warmest
              case 128:
                set16(d.mirekMin);
                break;
              case 129:
                set16(d.mirekMin);
                break; // PHYSICAL COOLEST ~ same as min for mock
              case 130:
                set16(d.mirekMax);
                break;
              case 131:
                set16(d.mirekMax);
                break; // PHYSICAL WARMEST ~ same as max for mock

              // Temporary values 192..208 from tmp snapshot
              case 192:
                set16(d.tmpX);
                break;
              case 193:
                set16(d.tmpY);
                break;
              case 194:
                set16(d.tmpMirek);
                break;
              case 195:
              case 196:
              case 197:
              case 198:
              case 199:
              case 200:
                {
                  final n = sel - 195;
                  final v = (n >= 0 && n < d.tmpPrimary.length) ? d.tmpPrimary[n] : 255;
                  set16(v);
                  break;
                }
              case 201:
                set16(d.tmpRGBWAF[0]);
                break;
              case 202:
                set16(d.tmpRGBWAF[1]);
                break;
              case 203:
                set16(d.tmpRGBWAF[2]);
                break;
              case 204:
                set16(d.tmpRGBWAF[3]);
                break;
              case 205:
                set16(d.tmpRGBWAF[4]);
                break;
              case 206:
                set16(d.tmpRGBWAF[5]);
                break;
              case 207:
                set16(0);
                break;
              case 208:
                set16(d.tmpColourType);
                break;

              // Report values 224..240 from current state
              case 224:
                set16(d.xyX);
                break;
              case 225:
                set16(d.xyY);
                break;
              case 226:
                set16(d.mirek);
                break;
              case 227:
              case 228:
              case 229:
              case 230:
              case 231:
              case 232:
                {
                  final n = sel - 227;
                  final v = (n >= 0 && n < d.primaryN.length) ? d.primaryN[n] : 255;
                  set16(v);
                  break;
                }
              case 233:
                set16(d.rgbwafChannels[0]);
                break;
              case 234:
                set16(d.rgbwafChannels[1]);
                break;
              case 235:
                set16(d.rgbwafChannels[2]);
                break;
              case 236:
                set16(d.rgbwafChannels[3]);
                break;
              case 237:
                set16(d.rgbwafChannels[4]);
                break;
              case 238:
                set16(d.rgbwafChannels[5]);
                break;
              case 239:
                set16(0);
                break;
              case 240:
                set16(d.colorType & 0xFF);
                break;

              default:
                // Any other value: leave DTR unchanged; return 0
                break;
            }
            return 0;
          }
        case 0x98:
          // getDTR on device: map according to last selector used in dt8.dart
          // Return DTR low (already set by 0xFA)
          switch (bus.dtr & 0xFF) {
            default:
              return bus.dtr & 0xFF;
          }
        case 0x9C:
          // Return DTR1 high (already set by 0xFA)
          return bus.dtr1 & 0xFF;
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

  /// Load a previously exported project JSON string back into the mock bus.
  /// Returns true on success.
  bool importProjectJson(String json) {
    try {
      final obj = jsonDecode(json);
      if (obj is Map<String, dynamic>) {
        bus.applyJson(obj);
        return true;
      }
    } catch (e) {
      DaliLog.instance.debugLog('Mock import failed: $e');
    }
    return false;
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
