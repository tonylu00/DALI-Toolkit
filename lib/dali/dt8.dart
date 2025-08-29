import 'log.dart';

import 'base.dart';
import 'color.dart';

class ColorStatus {
  int _status;
  ColorStatus(this._status);

  bool get xyOutOfRange => (_status & 0x01) == 0x01;
  set xyOutOfRange(bool value) => _status = value ? (_status | 0x01) : (_status & ~0x01);

  bool get ctOutOfRange => (_status & 0x02) == 0x02;
  set ctOutOfRange(bool value) => _status = value ? (_status | 0x02) : (_status & ~0x02);

  bool get autoCalibrationActive => (_status & 0x04) == 0x04;
  set autoCalibrationActive(bool value) => _status = value ? (_status | 0x04) : (_status & ~0x04);

  bool get autoCalibrationSuccess => (_status & 0x08) == 0x08;
  set autoCalibrationSuccess(bool value) => _status = value ? (_status | 0x08) : (_status & ~0x08);

  bool get xyActive => (_status & 0x10) == 0x10;
  set xyActive(bool value) => _status = value ? (_status | 0x10) : (_status & ~0x10);

  bool get ctActive => (_status & 0x20) == 0x20;
  set ctActive(bool value) => _status = value ? (_status | 0x20) : (_status & ~0x20);

  bool get primaryNActive => (_status & 0x40) == 0x40;
  set primaryNActive(bool value) => _status = value ? (_status | 0x40) : (_status & ~0x40);

  bool get rgbwafActive => (_status & 0x80) == 0x80;
  set rgbwafActive(bool value) => _status = value ? (_status | 0x80) : (_status & ~0x80);
}

class ColorType {
  static const none = 0xff;
  static const xy = 0x10;
  static const rgbWaf = 0x80;
  static const colorTemp = 0x20;
  static const primaryN = 0x40;
  static const unknown = 0x00;
}

class ColorTypeFeature {
  // Represents the 8-bit 'COLOUR TYPE FEATURES' (Command 249 / 0xF9).
  // Bit layout:
  // bit0: xy capable
  // bit1: colour temperature capable
  // bit2..4: number of primaries (0..6)
  // bit5..7: number of RGBWAF channels (0..6)
  final int _features;

  ColorTypeFeature(this._features);

  bool get xyCapable => (_features & 0x01) == 0x01;
  bool get ctCapable => (_features & 0x02) == 0x02;
  int get primaryCount => (_features >> 2) & 0x07; // 0..6 (spec)
  int get rgbwafChannels => (_features >> 5) & 0x07; // 0..6 (spec)

  bool get primaryNCapable => primaryCount > 0;
  bool get rgbwafCapable => rgbwafChannels > 0;
}

class DaliDT8 {
  final DaliBase base;

  DaliDT8(this.base);

  Future<int> getColorType(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(8);
    int result = await base.queryCmd(addr, 0xf9);
    return result;
  }

  Future<ColorStatus> getColorStatus(int a) async {
    int addr = a * 2 + 1;
    await base.dtSelect(8);
    int result = await base.queryCmd(addr, 0xf8);
    return ColorStatus(result);
  }

  Future<int> getColTempRaw(int a, [int? t]) async {
    // Map selector to DTR code per Table 11 and delegate to unified 0xFA path
    // t: 2 => current CT (2), 0 => coolest (128), 1 => warmest (130)
    // t: 3 => physical coolest (129), 4 => physical warmest (131)
    final type = t ?? 2;
    int selector;
    switch (type) {
      case 0:
        selector = 128;
        break;
      case 1:
        selector = 130;
        break;
      case 3:
        selector = 129;
        break;
      case 4:
        selector = 131;
        break;
      case 2:
      default:
        selector = 2;
        break;
    }
    // Respect capability: only block pure CT selector (2/128..131)
    final featuresByte = await getColorType(a);
    final features = ColorTypeFeature(featuresByte);
    if (!features.ctCapable) return 0;
    final v = await getColourRaw(a, selector);
    return v ?? 0;
  }

  Future<void> setColTempRaw(int a, int value) async {
    int dtr = 0;
    int dtr1 = 0;

    if (value < 0) {
      value = 0;
    } else if (value > 65535) {
      value = 65535;
    }

    dtr = value;
    while (dtr > 255) {
      dtr -= 256;
      dtr1++;
    }
    await base.setDTR(dtr);
    await base.setDTR1(dtr1);
    await base.dtSelect(8);
    await base.setDTRAsColourTemp(a);
    await base.dtSelect(8);
    await base.activate(a);
  }

  Future<void> setColorTemperature(int addr, int v) async {
    if (v == 0) v = 1;
    double mirekD = 1000000.0 / v;
    int mirek = mirekD.floor();
    await setColTempRaw(addr, mirek);
  }

  Future<int> getColorTemperature(int a) async {
    int? mirek = await getColourRaw(a, 2);
    if (mirek == null) return 0;
    double kelvin = 1000000.0 / mirek;
    return kelvin.floor();
  }

  Future<int> getMinColorTemperature(int a) async {
    int mirek = await getColTempRaw(a, 0);
    if (mirek == 0) return 0;
    double kelvin = 1000000.0 / mirek;
    return kelvin.floor();
  }

  Future<int> getMaxColorTemperature(int a) async {
    int mirek = await getColTempRaw(a, 1);
    if (mirek == 0) return 0;
    double kelvin = 1000000.0 / mirek;
    return kelvin.floor();
  }

  /// Physical CT range helpers (Table 11: 129/131)
  Future<int> getPhysicalMinColorTemperature(int a) async {
    int mirek = await getColTempRaw(a, 3);
    if (mirek == 0) return 0;
    double kelvin = 1000000.0 / mirek;
    return kelvin.floor();
  }

  Future<int> getPhysicalMaxColorTemperature(int a) async {
    int mirek = await getColTempRaw(a, 4);
    if (mirek == 0) return 0;
    double kelvin = 1000000.0 / mirek;
    return kelvin.floor();
  }

  Future<void> setColourRaw(int addr, int x1, int y1) async {
    int x1L = x1 & 0xff;
    int y1L = y1 & 0xff;
    int x1H = x1 >> 8;
    int y1H = y1 >> 8;

    int a = addr ~/ 2;
    await base.setDTR(x1L);
    await base.setDTR1(x1H);
    await base.dtSelect(8);
    await base.setDTRAsColourX(a);
    await base.setDTR(y1L);
    await base.setDTR1(y1H);
    await base.dtSelect(8);
    await base.setDTRAsColourY(a);
    await base.dtSelect(8);
    await base.activate(a);
  }

  Future<void> setColourRGBRaw(int addr, int r, int g, int b) async {
    int a = addr ~/ 2;
    await base.setDTR(r);
    await base.setDTR1(g);
    await base.setDTR2(b);
    await base.dtSelect(8);
    await base.setDTRAsColourRGB(a);
    await base.dtSelect(8);
    await base.activate(a);
  }

  Future<void> setColour(int a, double x, double y) async {
    if (x < 0 || x > 1) {
      x = 0;
    }
    if (y < 0 || y > 1) {
      y = 0;
    }
    int x1 = (x * 65535).floor();
    int y1 = (y * 65535).floor();
    int addr = a * 2 + 1;
    await setColourRaw(addr, x1, y1);
  }

  Future<int?> getColourRaw(int a, int type) async {
    final code = type & 0xFF;
    final featuresByte = await getColorType(a);
    final features = ColorTypeFeature(featuresByte);
    // Only CT-related codes require CT capability
    if ((code == 2 || code == 128 || code == 129 || code == 130 || code == 131) &&
        !features.ctCapable) {
      DaliLog.instance.debugLog('Device not supporting colour temperature (CT)');
      return null;
    }
    // For active-type related codes (0..15), log status but proceed
    if (code <= 15) {
      final status = await getColorStatus(a);
      if ((code == 0 || code == 1)) {
        if (status.xyOutOfRange) DaliLog.instance.debugLog('Color x/y out of range');
        if (!status.xyActive) DaliLog.instance.debugLog('x/y not active; attempting query');
      } else if (code == 2) {
        if (status.ctOutOfRange) DaliLog.instance.debugLog('CT out of range');
        if (!status.ctActive) DaliLog.instance.debugLog('CT not active; attempting query');
      }
    }
    await base.setDTR(code);
    await base.dtSelect(8);
    await base.queryColourValue(a);
    int dtr = await base.getDTR(a);
    int dtr1 = await base.getDTR1(a);
    int count = dtr1 * 256 + dtr;
    return count;
  }

  Future<List<double>> getColour(int a) async {
    final x = await getColourRaw(a, 0);
    final y = await getColourRaw(a, 1);
    if (x == null || y == null) {
      return [];
    }
    DaliLog.instance.debugLog('x: $x, y: $y');
    return [x / 65535, y / 65535];
  }

  Future<void> setColourRGB(int addr, int r, int g, int b) async {
    if (r < 0 || r > 255) {
      r = 0;
    }
    if (g < 0 || g > 255) {
      g = 0;
    }
    if (b < 0 || b > 255) {
      b = 0;
    }
    final xy = DaliColor.rgb2xy(r.toDouble(), g.toDouble(), b.toDouble());
    await setColour(addr, xy[0], xy[1]);
  }

  Future<List<int>> getColourRGB(int a) async {
    final xy = await getColour(a);
    if (xy.isEmpty) {
      return [];
    }
    DaliLog.instance.debugLog('xy: $xy');
    final rgb = DaliColor.xy2rgb(xy[0], xy[1]);
    return rgb;
  }

  // ----------------------------- Active-type related queries (Table 11: 3..15) -----------------------------
  /// PRIMARY N DIMLEVEL (active colour type related). N in [0..5].
  Future<int?> getPrimaryDimLevel(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 3 + n);
  }

  /// Individual RGBWAF dimlevels (active colour type related)
  Future<int?> getRedDimLevel(int a) async => getColourRaw(a, 9);
  Future<int?> getGreenDimLevel(int a) async => getColourRaw(a, 10);
  Future<int?> getBlueDimLevel(int a) async => getColourRaw(a, 11);
  Future<int?> getWhiteDimLevel(int a) async => getColourRaw(a, 12);
  Future<int?> getAmberDimLevel(int a) async => getColourRaw(a, 13);
  Future<int?> getFreecolourDimLevel(int a) async => getColourRaw(a, 14);
  Future<int?> getRGBWAFControl(int a) async => getColourRaw(a, 15);

  // ----------------------------- Temporary colour queries (Table 11: 192..208) -----------------------------
  Future<int?> getTemporaryXRaw(int a) async => getColourRaw(a, 192);
  Future<int?> getTemporaryYRaw(int a) async => getColourRaw(a, 193);
  Future<int?> getTemporaryColourTemperatureRaw(int a) async => getColourRaw(a, 194);

  /// TEMPORARY PRIMARY N DIMLEVEL (N in [0..5])
  Future<int?> getTemporaryPrimaryDimLevel(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 195 + n);
  }

  Future<int?> getTemporaryRedDimLevel(int a) async => getColourRaw(a, 201);
  Future<int?> getTemporaryGreenDimLevel(int a) async => getColourRaw(a, 202);
  Future<int?> getTemporaryBlueDimLevel(int a) async => getColourRaw(a, 203);
  Future<int?> getTemporaryWhiteDimLevel(int a) async => getColourRaw(a, 204);
  Future<int?> getTemporaryAmberDimLevel(int a) async => getColourRaw(a, 205);
  Future<int?> getTemporaryFreecolourDimLevel(int a) async => getColourRaw(a, 206);
  Future<int?> getTemporaryRGBWAFControl(int a) async => getColourRaw(a, 207);
  Future<int?> getTemporaryColourType(int a) async => getColourRaw(a, 208);

  /// Return TEMPORARY x/y as [x, y] in 0..1 range; empty list on MASK.
  Future<List<double>> getTemporaryColour(int a) async {
    final x = await getTemporaryXRaw(a);
    final y = await getTemporaryYRaw(a);
    if (x == null || y == null) return [];
    return [x / 65535.0, y / 65535.0];
  }

  /// Return TEMPORARY COLOUR TEMPERATURE (Kelvin)
  Future<int> getTemporaryColorTemperature(int a) async {
    final mirek = await getTemporaryColourTemperatureRaw(a) ?? 0;
    if (mirek == 0) return 0;
    return (1000000.0 / mirek).floor();
  }

  // ----------------------------- Report colour queries (Table 11: 224..240) -----------------------------
  Future<int?> getReportXRaw(int a) async => getColourRaw(a, 224);
  Future<int?> getReportYRaw(int a) async => getColourRaw(a, 225);
  Future<int?> getReportColourTemperatureRaw(int a) async => getColourRaw(a, 226);

  /// REPORT PRIMARY N DIMLEVEL (N in [0..5])
  Future<int?> getReportPrimaryDimLevel(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 227 + n);
  }

  Future<int?> getReportRedDimLevel(int a) async => getColourRaw(a, 233);
  Future<int?> getReportGreenDimLevel(int a) async => getColourRaw(a, 234);
  Future<int?> getReportBlueDimLevel(int a) async => getColourRaw(a, 235);
  Future<int?> getReportWhiteDimLevel(int a) async => getColourRaw(a, 236);
  Future<int?> getReportAmberDimLevel(int a) async => getColourRaw(a, 237);
  Future<int?> getReportFreecolourDimLevel(int a) async => getColourRaw(a, 238);
  Future<int?> getReportRGBWAFControl(int a) async => getColourRaw(a, 239);
  Future<int?> getReportColourType(int a) async => getColourRaw(a, 240);

  /// Return REPORT x/y as [x, y] in 0..1 range; empty list on MASK.
  Future<List<double>> getReportColour(int a) async {
    final x = await getReportXRaw(a);
    final y = await getReportYRaw(a);
    if (x == null || y == null) return [];
    DaliLog.instance.debugLog('report xy: x=$x, y=$y');
    return [x / 65535.0, y / 65535.0];
  }

  /// Return REPORT COLOUR TEMPERATURE (Kelvin)
  Future<int> getReportColorTemperature(int a) async {
    final mirek = await getReportColourTemperatureRaw(a) ?? 0;
    if (mirek == 0) return 0;
    return (1000000.0 / mirek).floor();
  }

  /// Query number of primaries (DTR=82). Returns null on MASK/no answer.
  Future<int?> getNumberOfPrimaries(int a) async {
    return await getColourRaw(a, 82);
  }

  /// Primary N info (x, y, TY) — DTR codes 64+3N, 65+3N, 66+3N (N: 0..5)
  Future<int?> getPrimaryXRaw(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 64 + 3 * n);
  }

  Future<int?> getPrimaryYRaw(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 65 + 3 * n);
  }

  Future<int?> getPrimaryTy(int a, int n) async {
    if (n < 0 || n > 5) return null;
    return await getColourRaw(a, 66 + 3 * n);
  }

  Future<List<double>> getSceneColor(int a, int sense) async {
    final bright = await base.getScene(a, sense);
    if (bright == 255) return []; //MASK
    await base.copyReportColourToTemp(a);
    final xy = await getColour(a);
    if (xy.isEmpty) {
      return [];
    }
    DaliLog.instance.debugLog('xy: $xy');
    return xy;
  }
}
