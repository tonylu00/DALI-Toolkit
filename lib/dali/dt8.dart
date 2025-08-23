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
  static const xy = 0x01;
  static const colorTemp = 0x02;
  static const primaryN = 0x04;
  static const rgbWaf = 0x08;
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
    int type = t ?? 2;
    if (type == 2) {
      await base.setDTR(2);
    } else if (type == 0) {
      await base.setDTR(128);
    } else if (type == 1) {
      await base.setDTR(130);
    }
    await base.dtSelect(8);

    int colorType = await getColorType(a);
    if (colorType != ColorType.colorTemp) {
      DaliLog.instance.debugLog('Device not supporting color mode');
      return 0;
    }

    ColorStatus status = await getColorStatus(a);
    if (status.ctOutOfRange) {
      DaliLog.instance.debugLog('Color temperature out of range');
      return 0;
    }
    if (!status.ctActive) {
      DaliLog.instance.debugLog('Color temperature not active');
      return 0;
    }

    int dtr = await base.getDTR(a);
    int dtr1 = await base.getDTR1(a);
    int value = dtr;
    while (dtr1 > 0) {
      value += 256;
      dtr1--;
    }
    DaliLog.instance.debugLog('Color temperature raw: $value');
    return value;
  }

  Future<void> setColTempRaw(int a, int value) async {
    int addr = a * 2 + 1;
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
    await base.sendExtCmd(addr, 0xe7);
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

  Future<void> setColourRaw(int addr, int x1, int y1) async {
    int x1L = x1 & 0xff;
    int y1L = y1 & 0xff;
    int x1H = x1 >> 8;
    int y1H = y1 >> 8;

    int trueAddr = (addr ~/ 2) * 2 + 1;
    await base.setDTR(x1L);
    await base.setDTR1(x1H);
    await base.dtSelect(8);
    await base.sendExtCmd(trueAddr, 0xe0);
    await base.setDTR(y1L);
    await base.setDTR1(y1H);
    await base.dtSelect(8);
    await base.sendExtCmd(trueAddr, 0xe1);
    await base.dtSelect(8);
    await base.activate(addr ~/ 2);
  }

  Future<void> setColourRGBRaw(int addr, int r, int g, int b) async {
    int trueAddr = (addr ~/ 2) * 2 + 1;
    await base.setDTR(r);
    await base.setDTR1(g);
    await base.setDTR2(b);
    await base.dtSelect(8);
    await base.sendExtCmd(trueAddr, 0xe2);
    await base.dtSelect(8);
    await base.activate(addr ~/ 2);
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
    int colorType = await getColorType(a);
    if (colorType == 0) {
      DaliLog.instance.debugLog('Device not supporting color mode');
      return null;
    }
    ColorStatus status = await getColorStatus(a);
    if ((type == 0 || type == 1) && status.xyOutOfRange) {
      DaliLog.instance.debugLog('Color out of range');
      return null;
    }
    if ((type == 0 || type == 1) && !status.xyActive) {
      DaliLog.instance.debugLog('Color not active');
      return null;
    }
    if (type == 2 && status.ctOutOfRange) {
      DaliLog.instance.debugLog('Color temperature out of range');
      return null;
    }
    if (type == 2 && !status.ctActive) {
      DaliLog.instance.debugLog('Color temperature not active');
      return null;
    }
    await base.setDTR(type);
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
}
