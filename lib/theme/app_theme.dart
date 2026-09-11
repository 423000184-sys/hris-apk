// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppColors — single source of truth for the DARK theme + brand colors
// ═══════════════════════════════════════════════════════════════════════════════
class AppColors {
  // ── Scaffold / Background ────────────────────────────────────────────────
  static const Color primary       = Color(0xFF080808);
  static const Color primaryDeep   = Color(0xFF111111);
  static const Color bg            = Color(0xFF111111);

  // ── Surface layers ────────────────────────────────────────────────────────
  static const Color surface       = Color(0xFF27272A);
  static const Color surface2      = Color(0xFF232323);
  static const Color surfaceLight  = Color(0xFF27272A);
  static const Color card          = Color(0xFF27272A);
  static const Color cardBorder    = Color(0xFF71717A);

  // ── Brand / Orange ────────────────────────────────────────────────────────
  static const Color orange        = Color(0xFFFF8A00);
  static const Color orangeHot     = Color(0xFFFA6A00);
  static const Color orangeGlow    = Color(0xFFFA6A00);
  static const Color orangeDark    = Color(0xFFF54900);

  // ── Status ────────────────────────────────────────────────────────────────
  static const Color success       = Color(0xFF39D98A);
  static const Color warning       = Color(0xFFFFAA00);
  static const Color error         = Color(0xFFFF0000);
  static const Color info          = Color(0xFF4DA3FF);

  // ── Semantic aliases ──────────────────────────────────────────────────────
  static const Color green         = Color(0xFF39D98A);
  static const Color red           = Color(0xFFFF0000);
  static const Color blue          = Color(0xFF4DA3FF);
  static const Color amber         = Color(0xFFFFAA00);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textMuted     = Color(0xFF555555);

  // ── White opacities ───────────────────────────────────────────────────────
  static const Color white         = Color(0xFFFFFFFF);
  static const Color white70       = Color(0xB3FFFFFF);
  static const Color white40       = Color(0x66FFFFFF);
  static const Color white15       = Color(0x26FFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient gradientOrange = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient gradientOrangeHot = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [orangeHot, orangeDark],
  );

  static const LinearGradient gradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E1E1E), Color(0xFF111111)],
  );

  static const LinearGradient gradientCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
  );

  static Color orangeDim(double opacity) => orange.withOpacity(opacity);
}

// ═══════════════════════════════════════════════════════════════════════════════
// AppPalette — Theme-aware colors, automatically switches with ThemeMode
// ═══════════════════════════════════════════════════════════════════════════════
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color card;
  final Color surface;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color fill;

  const AppPalette({
    required this.bg,
    required this.card,
    required this.surface,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.fill,
  });

  // ── DARK VALUES (default) ─────────────────────────────────────────────────
  static const AppPalette dark = AppPalette(
    bg:            Color(0xFF111111),
    card:          Color(0xFF27272A),
    surface:       Color(0xFF27272A),
    cardBorder:    Color(0xFF71717A),
    textPrimary:   Color(0xFFFFFFFF),
    textSecondary: Color(0xFF71717A),
    textMuted:     Color(0xFF555555),
    fill:          Color(0xFF232323),
  );

  // ── LIGHT VALUES ──────────────────────────────────────────────────────────
  static const AppPalette light = AppPalette(
    bg:            Color(0xFFF5F0ED),
    card:          Color(0xFFFFFFFF),
    surface:       Color(0xFFFFFFFF),
    cardBorder:    Color(0xFFE8E0D8),
    textPrimary:   Color(0xFF1A0A00),
    textSecondary: Color(0xFF5C3D1E),
    textMuted:     Color(0xFF8C6040),
    fill:          Color(0xFFEEE8E3),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? card,
    Color? surface,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? fill,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      surface: surface ?? this.surface,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      fill: fill ?? this.fill,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BuildContext extension — Easy access: context.palette.bg
// ═══════════════════════════════════════════════════════════════════════════════
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

// ═══════════════════════════════════════════════════════════════════════════════
// AppTheme
// ═══════════════════════════════════════════════════════════════════════════════
class AppTheme {

  // ── DARK THEME ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.primaryDeep,
      primaryColor: AppColors.primary,
      cardColor: AppColors.card,
      dividerColor: AppColors.cardBorder,

      extensions: const <ThemeExtension<dynamic>>[AppPalette.dark],

      colorScheme: const ColorScheme.dark(
        primary: AppColors.orange,
        secondary: AppColors.amber,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textPrimary,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),

      fontFamily: 'SF Pro Display',

      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -1.5),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1.0),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.25),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.5),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.65),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.6),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textMuted, height: 1.5, letterSpacing: 0.25),
        labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 1.5),
        labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1.0),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 2.0),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryDeep,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: IconThemeData(color: AppColors.textSecondary),
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: 2.0),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.orange.withOpacity(0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : const Color(0xFF444444)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange.withOpacity(0.35) : const Color(0xFF333333)),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : Colors.transparent),
        checkColor: WidgetStateProperty.all(AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange,
        linearTrackColor: AppColors.cardBorder,
        circularTrackColor: AppColors.cardBorder,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.orange,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.orange.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 10,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.orange : AppColors.textMuted,
        )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.orange : AppColors.textMuted,
          size: 22,
        )),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedColor: AppColors.orange.withOpacity(0.15),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        side: const BorderSide(color: AppColors.cardBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: AppColors.orange,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
        space: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.orange.withOpacity(0.3), width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        actionTextColor: AppColors.orange,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.orange.withOpacity(0.2), width: 1),
        ),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -0.5),
        contentTextStyle: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        modalElevation: 0,
        elevation: 0,
        dragHandleColor: AppColors.cardBorder,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: AppColors.surface,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.orange,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.orange,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.orange,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
        dividerColor: AppColors.cardBorder,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  // ── LIGHT THEME ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    const _bgColor     = Color(0xFFF5F0ED);
    const _cardColor   = Color(0xFFFFFFFF);
    const _borderColor = Color(0xFFE8E0D8);
    const _textMain    = Color(0xFF1A0A00);
    const _textSub     = Color(0xFF5C3D1E);
    const _textHint    = Color(0xFF8C6040);
    const _fillColor   = Color(0xFFEEE8E3);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _bgColor,
      primaryColor: _bgColor,
      cardColor: _cardColor,
      dividerColor: _borderColor,

      extensions: const <ThemeExtension<dynamic>>[AppPalette.light],

      colorScheme: const ColorScheme.light(
        primary: AppColors.orange,
        secondary: AppColors.amber,
        surface: _cardColor,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _textMain,
        onError: Colors.white,
      ),

      fontFamily: 'SF Pro Display',

      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _textMain, letterSpacing: -1.5),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _textMain, letterSpacing: -1.0),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textMain, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _textMain, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textMain),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textMain),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textMain, letterSpacing: 0.5),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textMain),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textSub),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: _textMain, height: 1.65),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: _textSub, height: 1.6),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _textHint, height: 1.5),
        labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _textMain, letterSpacing: 1.5),
        labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _textSub, letterSpacing: 1.0),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _textHint, letterSpacing: 2.0),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: _cardColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _textMain),
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _textMain, letterSpacing: 2.0),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _textMain,
          side: const BorderSide(color: _borderColor, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      cardTheme: CardThemeData(
        color: _cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
        labelStyle: const TextStyle(color: _textHint, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: Color(0xFFBBA080), fontSize: 13),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : Colors.grey),
        trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange.withOpacity(0.35) : Colors.grey.withOpacity(0.3)),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: _borderColor, width: 1.5),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange,
        linearTrackColor: _borderColor,
        circularTrackColor: _borderColor,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _cardColor,
        selectedItemColor: AppColors.orange,
        unselectedItemColor: Color(0xFF8C6040),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _cardColor,
        indicatorColor: AppColors.orange.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 10,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.orange : const Color(0xFF8C6040),
        )),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: _fillColor,
        selectedColor: AppColors.orange.withOpacity(0.12),
        labelStyle: const TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.w600),
        side: const BorderSide(color: _borderColor, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: AppColors.orange,
      ),

      dividerTheme: const DividerThemeData(color: _borderColor, thickness: 1, space: 0),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: _textMain,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.orange.withOpacity(0.3), width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        actionTextColor: AppColors.orange,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: _cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.orange.withOpacity(0.15), width: 1),
        ),
        titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textMain, letterSpacing: -0.5),
        contentTextStyle: const TextStyle(fontSize: 14, color: _textSub, height: 1.6),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _cardColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _cardColor,
        modalElevation: 0,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),

      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Color(0xFFEEE8E3),
        iconColor: _textSub,
        textColor: _textMain,
        selectedColor: AppColors.orange,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      iconTheme: const IconThemeData(color: _textSub, size: 22),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.orange,
        unselectedLabelColor: Color(0xFF8C6040),
        indicatorColor: AppColors.orange,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
        dividerColor: _borderColor,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: _cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _borderColor, width: 1),
        ),
        textStyle: const TextStyle(color: _textMain, fontSize: 13, fontWeight: FontWeight.w500),
      ),

      drawerTheme: const DrawerThemeData(
        backgroundColor: _cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}