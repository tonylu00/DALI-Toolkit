import 'package:flutter_test/flutter_test.dart';
import 'package:dalimaster/dali/color.dart';

void main() {
  group('DaliColor - xy/XYZ conversions', () {
    test('xy -> XYZ -> xy round trip', () {
      // D65 white
      const x = 0.312726;
      const y = 0.329023;
      final xyz = DaliColor.xy2xyz(x, y);
      final xy2 = DaliColor.xyz2xy(xyz[0], xyz[1], xyz[2]);
      expect(xy2[0], closeTo(x, 1e-6));
      expect(xy2[1], closeTo(y, 1e-6));
    });
  });

  group('DaliColor - RGB/XYZ/xy conversions', () {
    test('RGB(1,1,1) -> XYZ equals D65 constants', () {
      final xyz = DaliColor.rgb2xyz(1.0, 1.0, 1.0);
      expect(xyz[0], closeTo(0.950456, 1e-6));
      expect(xyz[1], closeTo(1.000000, 1e-6));
      expect(xyz[2], closeTo(1.088754, 1e-6));
    });

    test('XYZ(D65) -> RGB back to 255,255,255', () {
      final rgb = DaliColor.xyz2rgb(0.950456, 1.0, 1.088754);
      expect(rgb[0], 255);
      expect(rgb[1], 255);
      expect(rgb[2], 255);
    });

    test('RGB(1,1,1) -> xy equals D65 xy', () {
      final xy = DaliColor.rgb2xy(1.0, 1.0, 1.0);
      expect(xy[0], closeTo(0.312726, 1e-5));
      expect(xy[1], closeTo(0.329023, 1e-5));
    });

    test('xy(D65) -> RGB back to white', () {
      final rgb = DaliColor.xy2rgb(0.312726, 0.329023);
      expect(rgb[0], 255);
      expect(rgb[1], 255);
      expect(rgb[2], 255);
    });
  });

  group('DaliColor - LAB conversions', () {
    test('XYZ(D65) -> LAB approx 100,0,0', () {
      final lab = DaliColor.xyz2lab(0.950456, 1.0, 1.088754);
      expect(lab[0], closeTo(100.0, 1e-3));
      expect(lab[1], closeTo(0.0, 1e-2));
      expect(lab[2], closeTo(0.0, 1e-2));
    });

    test('LAB(100,0,0) -> XYZ ~ D65', () {
      final xyz = DaliColor.lab2xyz(100.0, 0.0, 0.0);
      expect(xyz[0], closeTo(0.950456, 1e-3));
      expect(xyz[1], closeTo(1.000000, 1e-3));
      expect(xyz[2], closeTo(1.088754, 1e-3));
    });
  });

  group('DaliColor - gamma & utils', () {
    test('gammaCorrection endpoints stable', () {
      final z = DaliColor.gammaCorrection(0, 0, 0);
      expect(z[0], 0);
      expect(z[1], 0);
      expect(z[2], 0);

      final o = DaliColor.gammaCorrection(1, 1, 1);
      expect(o[0], closeTo(1, 1e-9));
      expect(o[1], closeTo(1, 1e-9));
      expect(o[2], closeTo(1, 1e-9));
    });
  });
}
