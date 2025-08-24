import 'dart:convert';
import 'dart:math';

/// One simulated DALI device (DUT)
class MockDaliDevice {
  final int id; // 0..63, just an internal index
  int? shortAddress; // null => unaddressed
  int randH;
  int randM;
  int randL;
  bool isolated; // isolated from selection/compare (after withdraw)

  // Basic runtime state
  int brightness; // 0..254
  int groupBits; // 16-bit group membership
  final List<int> scenes; // 16 scenes brightness 0..254

  // Config fields
  int fadeTime; // 0..255
  int fadeRate; // 0..255
  int powerOnLevel; // 0..254
  int systemFailureLevel; // 0..254
  int minLevel; // 0..254
  int maxLevel; // 0..254
  int physicalMinLevel; // 0..254

  // DT/Version
  int deviceType; // e.g., 6 for DT6
  int extType; // vendor specific
  int version; // firmware version code

  // DT8/color state
  // ColorType: use constants from dali/dt8.dart, but avoid import here; mirror values
  // 0x20 => color temperature; 0x10 => xy; 0x80 => rgbWaf; 0x40 => primaryN
  int colorType;
  // Active mode flags (simplified): 'ct', 'xy', 'rgb'
  String activeColorMode;
  // xy 16-bit raw
  int xyX;
  int xyY;
  // xy gamut range for out-of-range checks
  int xyMinX;
  int xyMaxX;
  int xyMinY;
  int xyMaxY;
  // Color temperature raw (mirek, 16-bit)
  int mirek;
  int mirekMin; // minimum mirek (max Kelvin)
  int mirekMax; // maximum mirek (min Kelvin)

  // RGBWAF channels (R,G,B,W,A,F)
  final List<int> rgbwafChannels; // 6 elements 0..255
  // primaryN values (placeholder slots for 6 primaries)
  final List<int> primaryN;

  // --- DALI status bits (0x90) ---
  bool lampFailureFlag;
  bool limitErrorFlag;
  bool fadingCompletedFlag;
  bool resetStateFlag;
  bool psFaultFlag;

  MockDaliDevice({
    required this.id,
    this.shortAddress,
    required this.randH,
    required this.randM,
    required this.randL,
    this.isolated = false,
    this.brightness = 0,
    this.groupBits = 0,
    List<int>? scenes,
    this.fadeTime = 0,
    this.fadeRate = 0,
    this.powerOnLevel = 0,
    this.systemFailureLevel = 0,
    this.minLevel = 0,
    this.maxLevel = 254,
    this.physicalMinLevel = 0,
    this.deviceType = 6,
    this.extType = 0,
    this.version = 1,
    this.colorType = 0x20,
    this.activeColorMode = 'ct',
    this.xyX = 32768,
    this.xyY = 32768,
    this.xyMinX = 0,
    this.xyMaxX = 65535,
    this.xyMinY = 0,
    this.xyMaxY = 65535,
    this.mirek = 250,
    this.mirekMin = 153,
    this.mirekMax = 370,
    List<int>? rgbwafChannels,
    List<int>? primaryN,
    this.lampFailureFlag = false,
    this.limitErrorFlag = false,
    this.fadingCompletedFlag = true,
    this.resetStateFlag = false,
    this.psFaultFlag = false,
  })  : scenes = (scenes ?? List<int>.filled(16, 0)),
        rgbwafChannels = (rgbwafChannels ?? List<int>.filled(6, 0)),
        primaryN = (primaryN ?? List<int>.filled(6, 0));

  /// Lexicographic compare by H/M/L
  int compareLongAddrTo(int h, int m, int l) {
    if (randH != h) return randH.compareTo(h);
    if (randM != m) return randM.compareTo(m);
    return randL.compareTo(l);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shortAddress': shortAddress,
        'longAddress': {'H': randH, 'M': randM, 'L': randL},
        'isolated': isolated,
        'brightness': brightness,
        'groupBits': groupBits,
        'scenes': scenes,
        'fadeTime': fadeTime,
        'fadeRate': fadeRate,
        'powerOnLevel': powerOnLevel,
        'systemFailureLevel': systemFailureLevel,
        'minLevel': minLevel,
        'maxLevel': maxLevel,
        'physicalMinLevel': physicalMinLevel,
        'deviceType': deviceType,
        'extType': extType,
        'version': version,
        'dt8': {
          'colorType': colorType,
          'activeMode': activeColorMode,
          'xy': {'x': xyX, 'y': xyY},
          'gamut': {'xMin': xyMinX, 'xMax': xyMaxX, 'yMin': xyMinY, 'yMax': xyMaxY},
          'mirek': mirek,
          'mirekMin': mirekMin,
          'mirekMax': mirekMax,
          'rgbwaf': rgbwafChannels,
          'primaryN': primaryN,
        },
        'statusFlags': {
          'lampFailure': lampFailureFlag,
          'limitError': limitErrorFlag,
          'fadingCompleted': fadingCompletedFlag,
          'resetState': resetStateFlag,
          'psFault': psFaultFlag,
        },
      };

  static MockDaliDevice random(int id, {bool addressed = false, int? shortAddr}) {
    // Deterministic RNG for stable tests (seeded by id)
    final r = Random(id * 9973 + 12345);
    return MockDaliDevice(
      id: id,
      shortAddress: addressed ? (shortAddr ?? id.clamp(0, 63)) : null,
      randH: r.nextInt(256),
      randM: r.nextInt(256),
      randL: r.nextInt(256),
    );
  }
}

/// Mock DALI bus context (registers + devices)
class MockDaliBus {
  final List<MockDaliDevice> devices;
  int dtr = 0;
  int dtr1 = 0;
  int dtr2 = 0;
  int selH = 0;
  int selM = 0;
  int selL = 0;
  int? lastSelectedIndex; // set when programming or selection matched

  MockDaliBus._(this.devices);

  factory MockDaliBus.create({int deviceCount = 64}) {
    final list = List.generate(deviceCount, (i) => MockDaliDevice.random(i));
    return MockDaliBus._(list);
  }

  MockDaliDevice? deviceByShortAddr(int a) {
    for (final d in devices) {
      if (d.shortAddress == a) return d;
    }
    return null;
  }

  /// Find device index by exact long address (H,M,L), with optional filters.
  /// When [requireUnaddressed] is true, only match devices with null shortAddress.
  /// When [requireNotIsolated] is true, only match devices that are not isolated.
  int? indexByLongAddr(int h, int m, int l,
      {bool requireUnaddressed = false, bool requireNotIsolated = false}) {
    for (var i = 0; i < devices.length; i++) {
      final d = devices[i];
      if (requireUnaddressed && d.shortAddress != null) continue;
      if (requireNotIsolated && d.isolated) continue;
      if (d.randH == h && d.randM == m && d.randL == l) return i;
    }
    return null;
  }

  /// Returns indices of devices eligible for selection (unaddressed and not isolated)
  Iterable<int> _selectableIndices() sync* {
    for (var i = 0; i < devices.length; i++) {
      final d = devices[i];
      if (d.shortAddress == null && !d.isolated) yield i;
    }
  }

  /// Any device with long address < (selH, selM, selL)?
  bool anyCompareMatch() {
    for (final i in _selectableIndices()) {
      final d = devices[i];
      if (d.compareLongAddrTo(selH, selM, selL) < 0) return true;
    }
    return false;
  }

  MockDaliDevice? getSelectedDevice() {
    // Choose the device with the maximum long address that is still < selected (selH,selM,selL)
    int? chosenIdx;
    for (final i in _selectableIndices()) {
      final d = devices[i];
      if (d.compareLongAddrTo(selH, selM, selL) < 0) {
        if (chosenIdx == null) {
          chosenIdx = i;
        } else {
          final c = devices[chosenIdx];
          // If current device has a lexicographically larger long address, prefer it
          if (c.compareLongAddrTo(d.randH, d.randM, d.randL) < 0) {
            chosenIdx = i;
          }
        }
      }
    }
    return chosenIdx == null ? null : devices[chosenIdx];
  }

  /// The single device chosen when issuing Program Short Address after a compare
  /// We pick the device with the MAX longAddress that is < selected (selH,selM,selL)
  int? pickDeviceIndexForProgramming() {
    int? chosen;
    for (final i in _selectableIndices()) {
      if (devices[i].compareLongAddrTo(selH, selM, selL) < 0) {
        if (chosen == null) {
          chosen = i;
        } else {
          final c = devices[chosen];
          final di = devices[i];
          // choose the larger long address among matches (lexicographically greater)
          if (c.compareLongAddrTo(di.randH, di.randM, di.randL) < 0) {
            chosen = i;
          }
        }
      }
    }
    return chosen;
  }

  Map<String, dynamic> toJson({Map<String, dynamic>? meta}) => {
        if (meta != null) 'meta': meta,
        'devices': devices.map((e) => e.toJson()).toList(),
      };

  String exportJson({bool pretty = true, Map<String, dynamic>? meta}) {
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(toJson(meta: meta));
  }
}
