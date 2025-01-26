import 'dart:core';

import 'package:flutter/material.dart';
class DaliColor {
  static List<int> toIntList(Color color) {
    final a = (color.a * 255).toInt();
    final r = (color.r * 255).toInt();
    final g = (color.g * 255).toInt();
    final b = (color.b * 255).toInt();
    return [a, r, g, b];
  }

  static int toInt(Color color) {
    final c = toIntList(color);
    return (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | c[3];
  }

  static double decimalRound(int num, double idp) {
    double mult = mathPow(10, idp);
    return (num * mult + 0.5).floor() / mult;
  }

  /// Gamma correction for RGB color
  static List<double> gammaCorrection(double r, double g, double b, {double gamma = 2.8}) {
    double rr = mathPow(r, gamma);
    double gg = mathPow(g, gamma);
    double bb = mathPow(b, gamma);
    return [rr, gg, bb];
  }

  /// Converts RGB to XYZ
  static List<double> rgb2xyz(double r, double g, double b) {
    //r = r > 0.04045 ? mathPow((r + 0.055) / 1.055, 2.4) : r / 12.92;
    //g = g > 0.04045 ? mathPow((g + 0.055) / 1.055, 2.4) : g / 12.92;
    //b = b > 0.04045 ? mathPow((b + 0.055) / 1.055, 2.4) : b / 12.92;

    double x = 0.412453 * r + 0.357580 * g + 0.180423 * b;
    double y = 0.212671 * r + 0.715160 * g + 0.072169 * b;
    double z = 0.019334 * r + 0.119193 * g + 0.950227 * b;
    return [x, y, z];
  }

  /// Converts XYZ to RGB
  static List<int> xyz2rgb(double x, double y, double z) {
    double r =  3.2406 * x - 1.5372 * y - 0.4986 * z;
    double g = -0.9689 * x + 1.8758 * y + 0.0415 * z;
    double b =  0.0557 * x - 0.2040 * y + 1.0570 * z;

    // Apply gamma correction
    //r = r > 0.0031308 ? 1.055 * mathPow(r, 1.0 / 2.4) - 0.055 : 12.92 * r;
    //g = g > 0.0031308 ? 1.055 * mathPow(g, 1.0 / 2.4) - 0.055 : 12.92 * g;
    //b = b > 0.0031308 ? 1.055 * mathPow(b, 1.0 / 2.4) - 0.055 : 12.92 * b;

    // Clamp values to [0, 1]
    r = r.clamp(0.0, 1.0);
    g = g.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);

    // Convert to 8-bit integer
    return [(r * 255).round(), (g * 255).round(), (b * 255).round()];
  }

  /// Converts XYZ to xy
  static List<double> xyz2xy(double x, double y, double z) {
    double sum = x + y + z;
    if (sum == 0) return [0.0, 0.0];
    return [x / sum, y / sum];
  }

  /// Converts xy to XYZ
  static List<double> xy2xyz(double xVal, double yVal) {
    if (yVal == 0) return [0.0, 0.0, 0.0];
    double x = xVal * 1.0 / yVal;
    double y = 1.0;
    double z = (1.0 - xVal - yVal) / yVal;
    return [x, y, z];
  }

  /// Converts RGB to xy
  static List<double> rgb2xy(double r, double g, double b) {
    List<double> xyzVal = rgb2xyz(r, g, b);
    return xyz2xy(xyzVal[0], xyzVal[1], xyzVal[2]);
  }

  /// Converts xy to RGB
  static List<int> xy2rgb(double xVal, double yVal) {
    List<double> xyzVal = xy2xyz(xVal, yVal);
    return xyz2rgb(xyzVal[0], xyzVal[1], xyzVal[2]);
  }

  /// Converts XYZ to LAB (partial)
  static List<double> xyz2lab(double x, double y, double z) {
    double xn = 0.950456;
    double yn = 1.000000;
    double zn = 1.088754;
    double fx = x / xn;
    double fy = y / yn;
    double fz = z / zn;

    fx = (fx > 0.008856) ? mathPow(fx, 1.0 / 3.0) : (7.787 * fx) + (16.0 / 116.0);
    fy = (fy > 0.008856) ? mathPow(fy, 1.0 / 3.0) : (7.787 * fy) + (16.0 / 116.0);
    fz = (fz > 0.008856) ? mathPow(fz, 1.0 / 3.0) : (7.787 * fz) + (16.0 / 116.0);

    double l = (116.0 * fy) - 16.0;
    double a = 500.0 * (fx - fy);
    double b = 200.0 * (fy - fz);
    return [l, a, b];
  }

  /// Converts RGB to LAB (stub)
  static List<double> rgb2lab(double r, double g, double b) {
    List<double> xyzVal = rgb2xyz(r, g, b);
    return xyz2lab(xyzVal[0], xyzVal[1], xyzVal[2]);
  }

  /// Converts LAB to XYZ (stub)
  static List<double> lab2xyz(double l, double a, double b) {
    // Minimal placeholder
    double fy = (l + 16.0) / 116.0;
    double fx = fy + (a / 500.0);
    double fz = fy - (b / 200.0);

    double xr = (fx * fx * fx > 0.008856) ? (fx * fx * fx) : ((fx - (16.0 / 116.0)) / 7.787);
    double yr = (fy * fy * fy > 0.008856) ? (fy * fy * fy) : ((fy - (16.0 / 116.0)) / 7.787);
    double zr = (fz * fz * fz > 0.008856) ? (fz * fz * fz) : ((fz - (16.0 / 116.0)) / 7.787);

    double xn = 0.950456;
    double yn = 1.000000;
    double zn = 1.088754;

    double X = xr * xn;
    double Y = yr * yn;
    double Z = zr * zn;
    return [X, Y, Z];
  }

  /// Converts LAB to RGB (stub)
  static List<int> lab2rgb(double l, double a, double b) {
    List<double> xyzVal = lab2xyz(l, a, b);
    return xyz2rgb(xyzVal[0], xyzVal[1], xyzVal[2]);
  }

  /// (Misc placeholders for other color conversions if needed)
}

/// Simple math pow replacement
double mathPow(double base, double exp) => base == 0 && exp > 0 ? 0 : base.pow(exp);

extension _DoublePow on double {
  double pow(double exp) {
    // Minimal manual exponent
    return mathExp(exp * mathLog(this));
  }
}

double mathExp(double val) {
  // Very rough approximation or stub
  // Could integrate dart:math if needed
  return _expImpl(val);
}

double mathLog(double val) {
  // Very rough log stub
  return _lnImpl(val);
}

// These stubs can be replaced with real Dart math library calls if desired:
double _expImpl(double x) {
  // A simplified approach, or just mock
  // For actual usage, use dart:math
  // This is a placeholder
  double sum = 1.0;
  double term = 1.0;
  for (int i = 1; i < 20; i++) {
    term *= x / i;
    sum += term;
  }
  return sum;
}

double _lnImpl(double val) {
  // A minimal approximation for ln
  // For real usage, use math.log
  double guess = 0.0;
  double step = 0.1;
  while (mathExp(guess) < val) {
    guess += step;
  }
  return guess;
}