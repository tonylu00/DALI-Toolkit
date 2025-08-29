import 'package:easy_localization/easy_localization.dart';

// Standalone decoder; avoid importing base.dart to prevent import cycles.
// Minimal status bits struct for decoding 0x90 STATUS responses.
class DaliStatus {
  final int _status;
  DaliStatus(this._status);
  bool get controlGearPresent => (_status & 0x01) == 0x01;
  bool get lampFailure => (_status & 0x02) == 0x02;
  bool get lampPowerOn => (_status & 0x04) == 0x04;
  bool get limitError => (_status & 0x08) == 0x08;
  bool get fadingCompleted => (_status & 0x10) == 0x10;
  bool get resetState => (_status & 0x20) == 0x20;
  bool get missingShortAddress => (_status & 0x40) == 0x40;
  bool get psFault => (_status & 0x80) == 0x80;
}

/// Lightweight decoded record for UI rendering.
/// type: brightness | cmd | query | ext | special | response | unknown
class DecodedRecord {
  final String text;
  final String type;
  final int? addr;
  final int? cmd;
  final int? proto; // 0x10 send, 0x11 ext, 0x12 query; 0xFF response
  DecodedRecord(this.text, this.type, {this.addr, this.cmd, this.proto});
}

class DaliDecode {
  // Whether to append raw hex (addr/cmd/val) at the end of text
  bool displayRaw = true;

  // Track last queries for correlating 1-byte responses.
  int _lastQueryCmd = 0;
  DateTime _lastQueryAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Track DTR registers (write/read both)
  int dtr0 = 0;
  int dtr1 = 0;
  int dtr2 = 0;

  // When queryColourValue (0xFA) triggered, remember last DTR type (0/1/2 for x/y/ct per DT8.getColourRaw)
  int? _pendingColourType; // 0=x,1=y,2=ct
  DateTime _lastColourQueryAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Default response correlation window in ms (can be overridden by Settings)
  int responseWindowMs = 100;

  Map<int, String> cmd = {
    0x00: "OFF",
    0x01: "UP",
    0x02: "DOWN",
    0x03: "STEP_UP",
    0x04: "STEP_DOWN",
    0x05: "RECALL_MAX_LEVEL",
    0x06: "RECALL_MIN_LEVEL",
    0x07: "STEP_DOWN_AND_OFF",
    0x08: "ON_AND_STEP_UP",
    0x09: "ENABLE_DAPC_SEQUENCE",
    0x0A: "GO_TO_LAST_ACTIVE_LEVEL",
    0x0B: "CONTINUOUS_UP",
    0x0C: "CONTINUOUS_DOWN",
    // Extended/common configuration
    0x20: "RESET",
    0x21: "STORE_ACTUAL_LEVEL_IN_THE_DTR",
    0x22: "SAVE_PERSISTENT_VARIABLES",
    0x23: "SET_OPERATING_MODE",
    0x24: "RESET_MEMORY_BANK",
    0x25: "IDENTIFY_DEVICE",
    0x2A: "STORE_THE_DTR_AS_MAX_LEVEL",
    0x2B: "STORE_THE_DTR_AS_MIN_LEVEL",
    0x2C: "STORE_THE_DTR_AS_SYS_FAIL_LEVEL",
    0x2D: "STORE_THE_DTR_AS_PWR_ON_LEVEL",
    0x2E: "STORE_THE_DTR_AS_FADE_TIME",
    0x2F: "STORE_THE_DTR_AS_FADE_RATE",
    0x30: "SET_EXTENDED_FADE_TIME",
    0x80: "STORE_DTR_AS_SHORT_ADDRESS",
    0x90: "QUERY_STATUS",
    0x91: "QUERY_BALLAST",
    0x92: "QUERY_LAMP_FAILURE",
    0x93: "QUERY_LAMP_POWER_ON",
    0x94: "QUERY_LIMIT_ERROR",
    0x95: "QUERY_RESET_STATE",
    0x96: "QUERY_MISSING_SHORT_ADDRESS",
    0x97: "QUERY_VERSION_NUMBER",
    0x98: "QUERY_CONTENT_DTR",
    0x9C: "QUERY_CONTENT_DTR1",
    0x9D: "QUERY_CONTENT_DTR2",
    0x99: "QUERY_DEVICE_TYPE",
    0x9A: "QUERY_PHYSICAL_MINIMUM_LEVEL",
    0x9B: "QUERY_POWER_FAILURE",
    0x9E: "QUERY_OPERATING_MODE",
    0x9F: "QUERY_LIGHT_SOURCE_TYPE",
    0xA0: "QUERY_ACTUAL_LEVEL",
    0xA1: "QUERY_MAX_LEVEL",
    0xA2: "QUERY_MIN_LEVEL",
    0xA3: "QUERY_POWER_ON_LEVEL",
    0xA4: "QUERY_SYSTEM_FAILURE_LEVEL",
    0xA5: "QUERY_FADE_TIME/FADE_RATE",
    0xA6: "QUERY_MANUFACTURER_SPECIFIC_MODE",
    0xA7: "QUERY_NEXT_DEVICE_TYPE",
    0xA8: "QUERY_EXTENDED_FADE_TIME",
    0xAA: "QUERY_CONTROL_GEAR_FAILURE",
    0xC0: "QUERY_GROUPS_0-7",
    0xC1: "QUERY_GROUP_8-15",
    0xC2: "QUERY_RANDOM_ADDRESS_(H)",
    0xC3: "QUERY_RANDOM_ADDRESS_(M)",
    0xC4: "QUERY_RANDOM_ADDRESS_(L)",
    0xC5: "READ_MEMORY_LOCATION",
    0xE0: "STORE_DTR_AS_COLORX",
    0xE1: "STORE_DTR_AS_COLORY",
    0xE2: "ACTIVATE",
    0xE7: "SET_COLOR_TEMPERATURE",
    0xE8: "STEP_UP_COLOR_TEMPERATURE",
    0xE9: "STEP_DOWN_COLOR_TEMPERATURE",
    0xF8: "QUERY_COLOR_STATUS",
    0xF9: "QUERY_COLOR_TYPE",
    0xFA: "QUERY_COLOR_TEMPERATURE",
  };

  Map<int, String> sCMD = {
    0xA1: "TERMINATE",
    0xA3: "SET_DTR0",
    0xA5: "INITIALIZE",
    0xA7: "RANDOMIZE",
    0xA9: "COMPARE",
    0xAB: "WITHDRAW",
    0xB1: "SEARCHADDRH",
    0xB3: "SEARCHADDRM",
    0xB5: "SEARCHADDRL",
    0xB7: "PROGRAM_SHORT_ADDRESS",
    0xB9: "VERIFY_SHORT_ADDRESS",
    0xBB: "QUERY_SHORT_ADDRESS",
    0xBD: "PHYSICAL_SELECTION",
    0xC1: "DT_SELECT",
    0xC3: "SET_DTR_1",
    0xC5: "SET_DTR_2",
  };

  List<int> queryCmd = [
    // Core status queries
    0x90,
    0x91,
    0x92,
    0x93,
    0x94,
    0x95,
    0x96,
    0x97,
    0x98,
    0x99,
    0x9A,
    0x9B,
    0x9C,
    0x9D,
    0x9E,
    0x9F,
    0xA0,
    0xA1,
    0xA2,
    0xA3,
    0xA4,
    0xA5,
    0xA6,
    0xA7,
    0xA8,
    0xAA,
    // Scene level queries 0..15
    0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7,
    0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF,
    // Group and random address
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC4,
    0xC5,
    // DT8
    0xE2,
    0xE7,
    0xE8,
    0xE9,
    0xFA
  ];

  int isQueryCmd(int cmd) {
    if (queryCmd.contains(cmd)) {
      return 1;
    }
    return 0;
  }

  // ---------- Decoders ----------

  /// Decode direct arc power control (even address) as brightness level.
  DecodedRecord decodeBright(int addr, int level) {
    final who = _whoLabel(addr, even: true);
    final text = 'decode.dapc'.tr(namedArgs: {
      'hex': _hex(level),
      'val': '$level',
    });
    return _withRaw(DecodedRecord('$who $text', 'brightness', addr: addr, cmd: level, proto: 0x10));
  }

  /// Decode scene goto (0x10..0x1F)
  DecodedRecord decodeScene(int addr, int sceneCmd) {
    final sc = sceneCmd - 0x10;
    final who = _whoLabel(addr, even: false);
    final text = 'decode.go_to_scene'.tr(namedArgs: {'scene': '$sc'});
    return _withRaw(DecodedRecord('$who $text', 'cmd', addr: addr, cmd: sceneCmd, proto: 0x10));
  }

  /// Decode normal commands (odd address)
  DecodedRecord decodeCmd(int addr, int c) {
    final who = _whoLabel(addr, even: false);
    String name = cmd[c] ?? 'CMD 0x${_hex(c)}';
    // Dynamic ranges
    if (c >= 0x40 && c <= 0x4F) {
      name = 'SET_SCENE ${c - 0x40}';
    } else if (c >= 0x60 && c <= 0x6F) {
      name = 'ADD_TO_GROUP ${c - 0x60}';
    } else if (c >= 0x70 && c <= 0x7F) {
      name = 'REMOVE_FROM_GROUP ${c - 0x70}';
    }
    return _withRaw(DecodedRecord('$who $name', 'cmd', addr: addr, cmd: c, proto: 0x10));
  }

  /// Decode special (programming) commands (0x90..0xFC)
  DecodedRecord decodeSpCmd(int addr, int c) {
    // For sCMD frames, the first byte (addr param) is actually the COMMAND,
    // and the second byte (c param) is the DATA. There is no short address; all devices receive it.
    final cmdByte = addr & 0xFF;
    final dataByte = c & 0xFF;
    String name = sCMD[cmdByte] ?? 'SPECIAL_CMD 0x${_hex(cmdByte)}';
    String text;

    // Special queries in sCMD space: A9 COMPARE, B9 VERIFY_SHORT_ADDRESS, BB QUERY_SHORT_ADDRESS
    if (cmdByte == 0xA9 || cmdByte == 0xB9 || cmdByte == 0xBB) {
      return querySpCMD(cmdByte, dataByte);
    }
    // Track DTR writes (SET_DTRx)
    if (cmdByte == 0xA3) {
      dtr0 = dataByte;
      text = 'decode.dtr0'.tr(namedArgs: {
        'hex': _hex(dataByte),
        'val': '$dataByte',
        'bin': _bin(dataByte),
      });
    } else if (cmdByte == 0xC3) {
      dtr1 = dataByte;
      text = 'decode.dtr1'.tr(namedArgs: {
        'hex': _hex(dataByte),
        'val': '$dataByte',
        'bin': _bin(dataByte),
      });
    } else if (cmdByte == 0xC5) {
      dtr2 = dataByte;
      text = 'decode.dtr2'.tr(namedArgs: {
        'hex': _hex(dataByte),
        'val': '$dataByte',
        'bin': _bin(dataByte),
      });
    } else {
      text = 'decode.special_with_data'.tr(namedArgs: {
        'name': name,
        'hex': _hex(dataByte),
        'val': '$dataByte',
        'bin': _bin(dataByte),
      });
    }
    // For raw display, keep the original first/second bytes in addr/cmd fields
    return _withRaw(DecodedRecord(text, 'special', addr: addr, cmd: c, proto: 0x10));
  }

  /// Decode special-command queries (COMPARE/VERIFY_SHORT_ADDRESS/QUERY_SHORT_ADDRESS)
  DecodedRecord querySpCMD(int cmdByte, int dataByte) {
    _lastQueryCmd = cmdByte;
    _lastQueryAt = DateTime.now();
    final name = sCMD[cmdByte] ?? 'SPECIAL_CMD 0x${_hex(cmdByte)}';
    final text = 'decode.special_with_data'.tr(namedArgs: {
      'name': name,
      'hex': _hex(dataByte),
      'val': '$dataByte',
      'bin': _bin(dataByte),
    });
    // Use 'query' type for UI; keep proto as 0x10 because transport header remains 0x10
    return _withRaw(DecodedRecord(text, 'query', addr: cmdByte, cmd: dataByte, proto: 0x10));
  }

  /// Decode a query command (proto 0x12). This also arms response correlation.
  DecodedRecord decodeQuery(int addr, int c) {
    _lastQueryCmd = c;
    _lastQueryAt = DateTime.now();
    final who = _whoLabel(addr, even: false);
    String name = cmd[c] ?? 'QUERY 0x${_hex(c)}';
    // Dynamic names for scene level queries
    if (c >= 0xB0 && c <= 0xBF) {
      name = 'QUERY_SCENE_LEVEL ${c - 0xB0}';
    }
    if (c == 0xFA) {
      // DT8 Query colour value; dtr0 at this time should contain type (0/1/2 or 128/130)
      // Per DaliDT8.getColourRaw: await base.setDTR(type); then queryColourValue
      _lastColourQueryAt = DateTime.now();
      // Normalize known aliases
      int t = dtr0;
      if (t == 128) t = 0; // X
      if (t == 130) t = 1; // Y
      _pendingColourType = (t == 0 || t == 1 || t == 2) ? t : null;
      if (_pendingColourType != null) {
        final key = _pendingColourType == 0 ? 'x' : (_pendingColourType == 1 ? 'y' : 'ct');
        name = 'QUERY_COLOUR_VALUE($key)';
      }
    }
    return _withRaw(DecodedRecord('$who $name', 'query', addr: addr, cmd: c, proto: 0x12));
  }

  /// Decode a back frame (1 byte effective value; with gateway prefix 255 for OK)
  DecodedRecord decodeCmdResponse(int value, {int gwPrefix = 0xFF}) {
    final now = DateTime.now();
    final within = now.difference(_lastQueryAt).inMilliseconds <= responseWindowMs;
    if (!within || _lastQueryCmd == 0) {
      return _withRaw(DecodedRecord(
          'decode.unknown_back'.tr(namedArgs: {
            'hex': _hex(value),
            'val': '$value',
          }),
          'unknown',
          proto: 0xFF));
    }

    final c = _lastQueryCmd;

    // Version number
    if (c == 0x97) {
      return _withRaw(
          DecodedRecord('version = 0x${_hex(value)} / $value', 'response', cmd: c, proto: 0xFF));
    }

    // Fade time / fade rate (nibbles)
    if (c == 0xA5) {
      final ft = (value >> 4) & 0xF;
      final fr = value & 0xF;
      final ftText = ft == 0 ? 'no fade' : 'index $ft';
      final text = 'fade time = $ftText, fade rate code = $fr';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Extended fade time
    if (c == 0xA8) {
      final text = (value == 0) ? 'extended fade time = 0 ms' : 'extended fade time index = $value';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Decode known structures
    if (c == 0x90) {
      final ds = DaliStatus(value);
      final text = 'decode.status'.tr(namedArgs: {
        'gearFail': _yn(ds.psFault),
        'lampFail': _yn(ds.lampFailure),
        'lampOn': _yn(ds.lampPowerOn),
        'limit': _yn(ds.limitError),
        'fadingDone': _yn(ds.fadingCompleted),
        'reset': _yn(ds.resetState),
        'missingAddr': _yn(ds.missingShortAddress),
      });
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    if (c == 0x98) {
      dtr0 = value & 0xFF;
      // show like sample
      return _withRaw(DecodedRecord(
          'decode.dtr0'.tr(namedArgs: {
            'hex': _hex(value),
            'val': '$value',
            'bin': _bin(value),
          }),
          'response',
          cmd: c,
          proto: 0xFF));
    }
    if (c == 0x9C) {
      dtr1 = value & 0xFF;
      return _withRaw(DecodedRecord(
          'decode.dtr1'.tr(namedArgs: {
            'hex': _hex(value),
            'val': '$value',
            'bin': _bin(value),
          }),
          'response',
          cmd: c,
          proto: 0xFF));
    }
    if (c == 0x9D) {
      dtr2 = value & 0xFF;
      return _withRaw(DecodedRecord(
          'decode.dtr2'.tr(namedArgs: {
            'hex': _hex(value),
            'val': '$value',
            'bin': _bin(value),
          }),
          'response',
          cmd: c,
          proto: 0xFF));
    }

    // General boolean queries (YES/NO => 255/0)
    if ({0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x9B, 0xA6, 0xAA}.contains(c)) {
      final yes = value == 255;
      final name = cmd[c] ?? 'QUERY 0x${_hex(c)}';
      final yn = yes ? 'common.yes'.tr() : 'common.no'.tr();
      return _withRaw(DecodedRecord('$name => $yn', 'response', cmd: c, proto: 0xFF));
    }
    // Device type humanization
    if (c == 0x99) {
      final dtName = _deviceTypeName(value);
      final text = dtName != null
          ? 'QUERY_DEVICE_TYPE => $dtName (0x${_hex(value)} / $value)'
          : 'QUERY_DEVICE_TYPE => 0x${_hex(value)} / $value';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Light source type
    if (c == 0x9F) {
      final lsName = _lightSourceName(value);
      final text = lsName != null
          ? 'QUERY_LIGHT_SOURCE_TYPE => $lsName (0x${_hex(value)} / $value)'
          : 'QUERY_LIGHT_SOURCE_TYPE => 0x${_hex(value)} / $value';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Operating mode (0 = standard)
    if (c == 0x9E) {
      final text =
          (value == 0) ? 'QUERY_OPERATING_MODE => standard' : 'QUERY_OPERATING_MODE => $value';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Simple numeric wrappers to match common wording
    if (c == 0xA0) {
      return _withRaw(DecodedRecord('actual level = $value', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0x9A) {
      return _withRaw(DecodedRecord('physical minimum = $value', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0xA1) {
      return _withRaw(DecodedRecord('maximum level = $value', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0xA2) {
      return _withRaw(DecodedRecord('minimum level = $value', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0xA3) {
      return _withRaw(DecodedRecord('power on level = $value', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0xA4) {
      return _withRaw(
          DecodedRecord('system failure level = $value', 'response', cmd: c, proto: 0xFF));
    }

    // Scene level queries 0..15
    if (c >= 0xB0 && c <= 0xBF) {
      final idx = c - 0xB0;
      final text = (value == 0xFF) ? 'scene level $idx = MASK' : 'scene level $idx = $value';
      return _withRaw(DecodedRecord(text, 'response', cmd: c, proto: 0xFF));
    }

    // Group bitmap queries
    if (c == 0xC0 || c == 0xC1) {
      final base = (c == 0xC0) ? 0 : 8;
      final parts = <String>[];
      for (int i = 0; i < 8; i++) {
        final g = base + i;
        final yes = ((value >> i) & 1) == 1;
        parts.add('group $g = ${yes ? 'common.yes'.tr() : 'common.no'.tr()}');
      }
      return _withRaw(DecodedRecord(parts.join(', '), 'response', cmd: c, proto: 0xFF));
    }

    // Random address bytes
    if (c == 0xC2 || c == 0xC3 || c == 0xC4) {
      final which = (c == 0xC2)
          ? 'H'
          : (c == 0xC3)
              ? 'M'
              : 'L';
      return _withRaw(DecodedRecord(
          'random address ($which) = 0x${_hex(value)} / $value', 'response',
          cmd: c, proto: 0xFF));
    }

    // Read memory location
    if (c == 0xC5) {
      return _withRaw(DecodedRecord(
          'memory value = 0x${_hex(value)} / $value / ${_bin(value)}', 'response',
          cmd: c, proto: 0xFF));
    }

    // sCMD boolean-style queries
    if (c == 0xA9 || c == 0xB9) {
      final yes = (value == 255);
      final name = sCMD[c] ?? 'SPECIAL_CMD 0x${_hex(c)}';
      final yn = yes ? 'common.yes'.tr() : 'common.no'.tr();
      return _withRaw(DecodedRecord('$name => $yn', 'response', cmd: c, proto: 0xFF));
    }
    if (c == 0xBB) {
      // QUERY_SHORT_ADDRESS: show raw and derived short index when available
      if (value == 0xFF) {
        return _withRaw(
            DecodedRecord('QUERY_SHORT_ADDRESS => NONE', 'response', cmd: c, proto: 0xFF));
      }
      final shortIdx = value ~/ 2;
      return _withRaw(DecodedRecord(
          'QUERY_SHORT_ADDRESS => short $shortIdx (0x${_hex(value)} / $value)', 'response',
          cmd: c, proto: 0xFF));
    }

    // Colour value synthesis when possible
    if (_pendingColourType != null && now.difference(_lastColourQueryAt).inMilliseconds <= 1000) {
      // If after FA we subsequently read DTR0 and DTR1, combine to 16-bit value
      final combined = dtr1 * 256 + dtr0;
      final key = _pendingColourType == 0 ? 'x' : (_pendingColourType == 1 ? 'y' : 'ct');
      final pretty = _pendingColourType == 2
          ? 'mirek=$combined ~ K=${combined == 0 ? 0 : (1000000 ~/ combined)}'
          : '$key=${(combined / 65535).toStringAsFixed(4)} ($combined)';
      return _withRaw(DecodedRecord('${'decode.colour_value_prefix'.tr()} $pretty', 'response',
          cmd: c, proto: 0xFF));
    }

    // Numeric value default
    return _withRaw(DecodedRecord('0x${_hex(value)} / $value / ${_bin(value)}', 'response',
        cmd: c, proto: 0xFF));
  }

  /// High-level decode for front frames (proto/new header + addr/cmd).
  DecodedRecord decode(int addr, int c, {int proto = 0x10}) {
    // Special-programming commands: first byte is the command, second is data, from 0x90 to 0xFC
    if ((addr >= 0x90) && (addr <= 0xFC)) {
      return decodeSpCmd(addr, c);
    }
    // Query first (track for response correlation)
    if (proto == 0x12 || isQueryCmd(c) == 1) {
      return decodeQuery(addr, c);
    }
    // DAPC (brightness) if even address
    if ((addr & 1) == 0) {
      return decodeBright(addr, c);
    }
    // Scene 0x10..0x1F
    if (c >= 0x10 && c <= 0x1F) {
      return decodeScene(addr, c);
    }
    // Extended commands (proto 0x11): still decode with cmd table; 0xFA special handling
    if (proto == 0x11) {
      if (c == 0xFA) {
        // Same handling as queryColourValue
        return decodeQuery(addr, c);
      }
      final who = _whoLabel(addr, even: false);
      final name = cmd[c] ?? 'EXT 0x${_hex(c)}';
      return _withRaw(DecodedRecord('$who $name', 'ext', addr: addr, cmd: c, proto: proto));
    }
    return decodeCmd(addr, c);
  }

  // ---------- helpers ----------
  String _hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  String _bin(int v) => v.toRadixString(2).padLeft(8, '0');
  String _yn(bool b) => b ? 'common.yes'.tr() : 'common.no'.tr();

  // Unified address -> label for UI
  // even=true for DAPC (even address), false for odd-address frames (commands/queries)
  String _whoLabel(int addr, {required bool even}) {
    if (even) {
      if (addr == 0xFE) return 'broadcast';
      if (addr >= 0x80 && addr <= 0x8F) {
        return 'decode.group'.tr(namedArgs: {'addr': '${addr - 0x80}'});
      }
      return 'decode.short'.tr(namedArgs: {'addr': '${addr ~/ 2}'});
    } else {
      if (addr == 0xFF) return 'broadcast';
      if (addr >= 0x80 && addr <= 0x8F) {
        return 'decode.group'.tr(namedArgs: {'addr': '${addr - 0x80}'});
      }
      return 'decode.short'.tr(namedArgs: {'addr': '${(addr - 1) ~/ 2}'});
    }
  }

  // Try to humanize common device types (subset used in captures)
  String? _deviceTypeName(int v) {
    const map = {
      0x00: 'general control gear',
      0x01: 'self-contained emergency',
      0x02: 'converter',
      0x03: 'discharge (HID)',
      0x04: 'low-pressure sodium',
      0x05: 'incandescent/halogen',
      0x06: 'LED control gear',
      0x07: 'switching control',
      0x08: 'colour control (DT8)',
    };
    return map[v];
  }

  // Try to humanize common light source types
  String? _lightSourceName(int v) {
    const map = {
      0x00: 'fluorescent',
      0x01: 'compact fluorescent',
      0x02: 'high intensity discharge',
      0x03: 'low pressure sodium',
      0x04: 'incandescent/halogen',
      0x05: 'cold cathode',
      0x06: 'LED',
      0x07: 'other',
    };
    return map[v];
  }

  DecodedRecord _withRaw(DecodedRecord r) {
    if (!displayRaw) return r;
    final parts = <String>[];
    if (r.addr != null) parts.add('0x${_hex(r.addr!)}');
    if (r.cmd != null) parts.add('0x${_hex(r.cmd!)}');
    if (parts.isEmpty) return r;
    return DecodedRecord('${r.text}  [${parts.join(', ')}]', r.type,
        addr: r.addr, cmd: r.cmd, proto: r.proto);
  }
}
