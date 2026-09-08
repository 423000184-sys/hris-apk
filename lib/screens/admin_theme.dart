import 'package:flutter/material.dart';

class AdminTheme {
  static const Color orange = Color(0xFFE8994A);
  static const Color orangeLight = Color(0xFFFFF4E6);
  static const Color orangeText = Color(0xFFA05A00);
  static const Color dark = Color(0xFF1C1C1A);
  static const Color dark2 = Color(0xFF2A2A28);
  static const Color body = Color(0xFFF5F4F0);
  static const Color white = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE8E6E0);
  static const Color borderLight = Color(0xFFEEEDE8);
  static const Color surface = Color(0xFFFAFAFB);
  static const Color muted = Color(0xFF999999);
  static const Color text = Color(0xFF1A1A18);
  static const Color textMuted = Color(0xFF888888);
  static const Color green = Color(0xFF1A7A45);
  static const Color greenLight = Color(0xFFE8F9F0);
  static const Color red = Color(0xFFA02020);
  static const Color redLight = Color(0xFFFEEAEA);
  static const Color blue = Color(0xFF1A4FAA);
  static const Color blueLight = Color(0xFFE8F0FE);
  static const Color grayAvatar = Color(0xFFF0EFEA);
  static const Color grayText = Color(0xFF555555);
  static const Color navBg = Color(0xFF1C1C1A);
  static const Color navText = Color(0x73FFFFFF);
  static const Color navDivider = Color(0x14FFFFFF);

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;

  static const double radiusSm = 6;
  static const double radius = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 12;
  static const double radiusPill = 20;

  static const double textXS = 10;
  static const double textSm = 11;
  static const double textBase = 12.5;
  static const double textMd = 13;
  static const double textLg = 14;
  static const double textXl = 20;
  static const double text2xl = 26;

  static BoxDecoration card({double r = AdminTheme.radiusMd, Color? bg}) => BoxDecoration(
    color: bg ?? AdminTheme.white,
    borderRadius: BorderRadius.circular(r),
    border: Border.all(color: AdminTheme.border, width: 0.5),
  );
} 