import 'package:flutter/material.dart';

abstract final class AetherColors {
  static const background = Color(0xFF1B1C20);
  static const paper = Color(0xFFE9E3D9);
  static const sage = Color(0xFFA9B69A);
  static const magenta = Color(0xFFE94E91);
  static const blue = Color(0xFF485CC7);
  static const panel = Color(0xFF27282D);
  static const raised = Color(0xFF35363D);
  static const secondaryText = Color(0xFFAAA8B0);
  static const grid = Color(0xFF2D2E34);
}

abstract final class AetherTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AetherColors.sage,
      secondary: AetherColors.magenta,
      surface: AetherColors.panel,
      error: Color(0xFFFF7777),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AetherColors.background,
      canvasColor: AetherColors.background,
      dividerColor: AetherColors.raised,
      appBarTheme: const AppBarTheme(
        backgroundColor: AetherColors.background,
        foregroundColor: AetherColors.paper,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: AetherColors.paper, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleMedium: TextStyle(color: AetherColors.paper, fontSize: 14, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: AetherColors.paper, fontSize: 13),
        bodySmall: TextStyle(color: AetherColors.secondaryText, fontSize: 11),
        labelMedium: TextStyle(color: AetherColors.secondaryText, fontSize: 11, letterSpacing: 0.3),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AetherColors.raised, borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(color: AetherColors.paper, fontSize: 12),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AetherColors.sage,
        inactiveTrackColor: AetherColors.raised,
        thumbColor: AetherColors.paper,
        overlayColor: AetherColors.sage.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
    );
  }
}
