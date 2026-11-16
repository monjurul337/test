import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg = Color(0xFF0A0B10);
  static const Color drawerBg = Color(0xFF0F1118);
  static const Color cardBg = Color(0xFF131620);
  static const Color iconBoxBg = Color(0xFF1A1E2B);
  static const Color border = Color(0xFF1F2433);
  static const Color primary = Color(0xFF5C7CFA);
  static const Color primarySecondary = Color(0xFF7C5CFF);
  static const Color primaryLight = Color(0xFF93ADFF);
  static const Color activePill = Color(0xFF1B2238);
  static const Color textPrimary = Color(0xFFF5F7FB);
  static const Color textMuted = Color(0xFF8891A5);
  static const Color danger = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);

  static const Color lightBg = Color(0xFFF6F8FC);
  static const Color lightDrawerBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightIconBox = Color(0xFFF0F3F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightActivePill = Color(0xFFE0E7FF);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightMuted = Color(0xFF64748B);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bgOf(BuildContext context) => isDark(context) ? bg : lightBg;
  static Color drawerOf(BuildContext context) => isDark(context) ? drawerBg : lightDrawerBg;
  static Color cardOf(BuildContext context) => isDark(context) ? cardBg : lightSurface;
  static Color iconBoxOf(BuildContext context) => isDark(context) ? iconBoxBg : lightIconBox;
  static Color borderOf(BuildContext context) => isDark(context) ? border : lightBorder;
  static Color textOf(BuildContext context) => isDark(context) ? textPrimary : lightText;
  static Color mutedOf(BuildContext context) => isDark(context) ? textMuted : lightMuted;
  static Color activePillOf(BuildContext context) => isDark(context) ? activePill : lightActivePill;
  static Color accentTextOf(BuildContext context) => isDark(context) ? primaryLight : primary;
}

class AppTheme {
  static TextTheme _nexaBase(TextTheme base, Color primaryText) {
    return GoogleFonts.plusJakartaSansTextTheme(base)
        .apply(fontFamily: 'Nexa', bodyColor: primaryText, displayColor: primaryText);
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.primarySecondary,
        surface: AppColors.cardBg,
        error: AppColors.danger,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: _nexaBase(base.textTheme, AppColors.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.iconBoxBg,
        selectedColor: AppColors.activePill,
        labelStyle: const TextStyle(fontFamily: 'Nexa', fontSize: 12, color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(fontFamily: 'Nexa', fontSize: 12, color: AppColors.primaryLight),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.drawerBg,
        indicatorColor: AppColors.activePill,
        height: 64,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.primaryLight : AppColors.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Nexa',
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primaryLight : AppColors.textMuted,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.iconBoxBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.primarySecondary,
        surface: AppColors.lightSurface,
        error: AppColors.danger,
        onSurface: AppColors.lightText,
      ),
      textTheme: _nexaBase(base.textTheme, AppColors.lightText),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBg,
        foregroundColor: AppColors.lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.lightText),
        titleTextStyle: TextStyle(
          fontFamily: 'Nexa',
          color: AppColors.lightText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightIconBox,
        selectedColor: AppColors.lightActivePill,
        labelStyle: const TextStyle(fontFamily: 'Nexa', fontSize: 12, color: AppColors.lightText),
        secondaryLabelStyle: const TextStyle(fontFamily: 'Nexa', fontSize: 12, color: AppColors.primary),
        side: const BorderSide(color: AppColors.lightBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.lightBorder, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.lightActivePill,
        height: 64,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.primary : AppColors.lightMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Nexa',
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.lightMuted,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightIconBox,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.lightMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.lightMuted, fontSize: 13),
      ),
    );
  }
}
