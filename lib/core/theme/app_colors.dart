import 'package:flutter/material.dart';

/// CCTV Security-themed color palette.
/// Dark charcoal backgrounds with blue/cyan accents.
class AppColors {
  AppColors._();

  // Background
  static const Color background = Color(0xFF0D1117);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceVariant = Color(0xFF21262D);
  static const Color cardBackground = Color(0xFF1C2128);

  // Primary - Blue/Cyan
  //
  // `primary` is the *accent* colour: icons, borders, focus rings, map
  // markers and outlined-button strokes on dark backgrounds. It must stay
  // bright.
  static const Color primary = Color(0xFF58A6FF);
  // Filled surface for primary buttons. Dark enough that `textOnPrimary`
  // (white) reaches WCAG AA - it scores 7.8:1 versus the 2.5:1 that `primary`
  // gives, which made button labels unreadable.
  static const Color primarySurface = Color(0xFF0B4FA8);
  static const Color primaryDark = Color(0xFF1F6FEB);
  static const Color primaryLight = Color(0xFF79C0FF);
  static const Color accent = Color(0xFF39D2C0);

  // Status
  static const Color success = Color(0xFF3FB950);
  static const Color warning = Color(0xFFD29922);
  static const Color danger = Color(0xFFF85149);
  static const Color info = Color(0xFF58A6FF);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textTertiary = Color(0xFF6E7681);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Borders
  static const Color border = Color(0xFF30363D);
  static const Color borderLight = Color(0xFF21262D);

  // Map
  static const Color mapMarker = Color(0xFF58A6FF);
  static const Color mapCluster = Color(0xFF1F6FEB);
  static const Color mapClusterText = Color(0xFFFFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1F6FEB), Color(0xFF58A6FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF0D1117), Color(0xFF161B22)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1C2128), Color(0xFF161B22)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shadows
  static const Color shadow = Color(0x40000000);
}
