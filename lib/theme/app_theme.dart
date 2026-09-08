import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AppColors — single source of truth for every color in the app
// ═══════════════════════════════════════════════════════════════════════════════
class AppColors {

  // ── Scaffold / Background ────────────────────────────────────────────────────
  static const Color primary       = Color(0xFF080808);
  static const Color primaryDeep   = Color(0xFF111111); // main scaffold bg
  static const Color bg            = Color(0xFF111111); // alias for primaryDeep

  // ── Surface layers ───────────────────────────────────────────────────────────
  static const Color surface       = Color(0xFF27272A);
  static const Color surface2      = Color(0xFF232323);
  static const Color surfaceLight  = Color(0xFF27272A); // alias for surface
  static const Color card          = Color(0xFF27272A);
  static const Color cardBorder    = Color(0xFF71717A);

  // ── Brand / Orange ───────────────────────────────────────────────────────────
  // Updated to match the custom gradient stops: 0% FF8A00 → 50% FA6A00 → 100% F54900
  static const Color orange        = Color(0xFFFF8A00);
  static const Color orangeHot     = Color(0xFFFA6A00);
  static const Color orangeGlow    = Color(0xFFFA6A00);
  static const Color orangeDark    = Color(0xFFF54900);

  // ── Status ───────────────────────────────────────────────────────────────────
  static const Color success       = Color(0xFF39D98A); // green
  static const Color warning       = Color(0xFFFFAA00); // amber/yellow
  static const Color error         = Color(0xFFFF0000); // red/danger
  static const Color info          = Color(0xFF4DA3FF); // blue

  // ── Extra semantic aliases ───────────────────────────────────────────────────
  static const Color green         = Color(0xFF39D98A); // = success
  static const Color red           = Color(0xFFFF0000); // = error
  static const Color blue          = Color(0xFF4DA3FF); // = info
  static const Color amber         = Color(0xFFFFAA00); // = warning

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textMuted     = Color(0xFF555555);

  // ── White opacities (for inline use) ─────────────────────────────────────────
  static const Color white         = Color(0xFFFFFFFF);
  static const Color white70       = Color(0xB3FFFFFF);
  static const Color white40       = Color(0x66FFFFFF);
  static const Color white15       = Color(0x26FFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  // Custom 3-stop gradient: 0% FF8A00 → 50% FA6A00 → 100% F54900
  static const LinearGradient gradientOrange = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFFF8A00), // 0%
      Color(0xFFFA6A00), // 50%
      Color(0xFFF54900), // 100%
    ],
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

  // ── Helper: orange with opacity ───────────────────────────────────────────────
  static Color orangeDim(double opacity) => orange.withOpacity(opacity);
}

// ═══════════════════════════════════════════════════════════════════════════════
// AppTheme
// ═══════════════════════════════════════════════════════════════════════════════
class AppTheme {

  // ── DARK THEME (primary) ──────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.primaryDeep,
      primaryColor: AppColors.primary,
      cardColor: AppColors.card,
      dividerColor: AppColors.cardBorder,

      colorScheme: const ColorScheme.dark(
        primary:    AppColors.orange,
        secondary:  AppColors.amber,
        surface:    AppColors.surface,
        error:      AppColors.error,
        onPrimary:  AppColors.textPrimary,
        onSecondary:AppColors.textPrimary,
        onSurface:  AppColors.textPrimary,
        onError:    AppColors.textPrimary,
      ),

      fontFamily: 'SF Pro Display',

      // ── Text theme ──────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 36, fontWeight: FontWeight.w900,
          color: AppColors.textPrimary, letterSpacing: -1.5,
        ),
        displayMedium: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary, letterSpacing: -1.0,
        ),
        displaySmall: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary, letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary, letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary, letterSpacing: -0.25,
        ),
        headlineSmall: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary, letterSpacing: 0.5,
        ),
        titleMedium: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w400,
          color: AppColors.textPrimary, height: 1.65,
        ),
        bodyMedium: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w400,
          color: AppColors.textSecondary, height: 1.6,
        ),
        bodySmall: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400,
          color: AppColors.textMuted, height: 1.5, letterSpacing: 0.25,
        ),
        labelLarge: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary, letterSpacing: 1.5,
        ),
        labelMedium: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 1.0,
        ),
        labelSmall: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppColors.textMuted, letterSpacing: 2.0,
        ),
      ),

      // ── AppBar ───────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryDeep,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: IconThemeData(color: AppColors.textSecondary),
        titleTextStyle: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w900,
          color: AppColors.textPrimary, letterSpacing: 2.0,
        ),
      ),

      // ── Elevated button ──────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.orange.withOpacity(0.4),
          disabledForegroundColor: AppColors.textPrimary.withOpacity(0.5),
          elevation: 0,
          shadowColor: AppColors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          textStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Card ─────────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Input / TextField ────────────────────────────────────────────────────
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.cardBorder.withOpacity(0.5), width: 1),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),

      // ── Switch ───────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected)
            ? AppColors.orange
            : const Color(0xFF444444)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected)
            ? AppColors.orange.withOpacity(0.35)
            : const Color(0xFF333333)),
      ),

      // ── Checkbox ─────────────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected)
            ? AppColors.orange
            : Colors.transparent),
        checkColor: WidgetStateProperty.all(AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
      ),

      // ── Radio ────────────────────────────────────────────────────────────────
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected)
            ? AppColors.orange
            : AppColors.textMuted),
      ),

      // ── Slider ───────────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.orange,
        inactiveTrackColor: AppColors.cardBorder,
        thumbColor: AppColors.orange,
        overlayColor: AppColors.orange.withOpacity(0.15),
        valueIndicatorColor: AppColors.orange,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),

      // ── Progress indicator ───────────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange,
        linearTrackColor: AppColors.cardBorder,
        circularTrackColor: AppColors.cardBorder,
      ),

      // ── Bottom navigation bar ────────────────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.orange,
        unselectedItemColor: AppColors.textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),

      // ── Navigation bar (Material 3) ──────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.orange.withOpacity(0.15),
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 10,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? AppColors.orange
              : AppColors.textMuted,
        )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? AppColors.orange
              : AppColors.textMuted,
          size: 22,
        )),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceLight,
        selectedColor: AppColors.orange.withOpacity(0.15),
        disabledColor: AppColors.surfaceLight.withOpacity(0.5),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: AppColors.cardBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: AppColors.orange,
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.cardBorder,
        thickness: 1,
        space: 0,
      ),

      // ── SnackBar ─────────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(
          color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.orange.withOpacity(0.3), width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        actionTextColor: AppColors.orange,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.orange.withOpacity(0.2), width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900,
          color: AppColors.textPrimary, letterSpacing: -0.5,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14, color: AppColors.textSecondary, height: 1.6,
        ),
      ),

      // ── Bottom sheet ─────────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        modalElevation: 0,
        elevation: 0,
        dragHandleColor: AppColors.cardBorder,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // ── List tile ────────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: AppColors.surface,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.orange,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),

      // ── Icon ─────────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 22,
      ),

      // ── Tab bar ──────────────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.orange,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.orange,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5,
        ),
        dividerColor: AppColors.cardBorder,
        overlayColor: WidgetStateProperty.all(AppColors.orange.withOpacity(0.08)),
      ),

      // ── Floating action button ────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // ── Popup menu ───────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        textStyle: const TextStyle(
          color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500,
        ),
      ),

      // ── Tooltip ──────────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        textStyle: const TextStyle(
          color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Drawer ───────────────────────────────────────────────────────────────
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),

      // ── Search bar ───────────────────────────────────────────────────────────
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(AppColors.surfaceLight),
        elevation: WidgetStateProperty.all(0),
        side: WidgetStateProperty.all(const BorderSide(color: AppColors.cardBorder, width: 1)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
        hintStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      ),
    );
  }

  // ── LIGHT THEME ───────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    const _bgColor       = Color(0xFFF5F0ED);
    const _cardColor     = Color(0xFFFFFFFF);
    const _borderColor   = Color(0xFFE8E0D8);
    const _textMain      = Color(0xFF1A0A00);
    const _textSub       = Color(0xFF5C3D1E);
    const _textHint      = Color(0xFF8C6040);
    const _fillColor     = Color(0xFFEEE8E3);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _bgColor,
      primaryColor: _bgColor,
      cardColor: _cardColor,
      dividerColor: _borderColor,

      colorScheme: const ColorScheme.light(
        primary:     AppColors.orange,
        secondary:   AppColors.amber,
        surface:     _cardColor,
        error:       AppColors.error,
        onPrimary:   Colors.white,
        onSecondary: Colors.white,
        onSurface:   _textMain,
        onError:     Colors.white,
      ),

      fontFamily: 'SF Pro Display',

      // ── Text theme ──────────────────────────────────────────────────────────
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

      // ── AppBar ───────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: _cardColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: _textMain),
        titleTextStyle: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w900,
          color: _textMain, letterSpacing: 2.0,
        ),
      ),

      // ── Elevated button ──────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.orange.withOpacity(0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      // ── Outlined button ──────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _textMain,
          side: const BorderSide(color: _borderColor, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),

      // ── Text button ──────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),

      // ── Card ─────────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: _cardColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Input / TextField ────────────────────────────────────────────────────
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: const TextStyle(color: _textHint, fontSize: 13, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: Color(0xFFBBA080), fontSize: 13),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
      ),

      // ── Switch ───────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : Colors.grey),
        trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected)
            ? AppColors.orange.withOpacity(0.35)
            : Colors.grey.withOpacity(0.3)),
      ),

      // ── Checkbox ─────────────────────────────────────────────────────────────
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? AppColors.orange : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: _borderColor, width: 1.5),
      ),

      // ── Progress indicator ───────────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.orange,
        linearTrackColor: _borderColor,
        circularTrackColor: _borderColor,
      ),

      // ── Bottom navigation bar ────────────────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _cardColor,
        selectedItemColor: AppColors.orange,
        unselectedItemColor: Color(0xFF8C6040),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),

      // ── Navigation bar (Material 3) ──────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _cardColor,
        indicatorColor: AppColors.orange.withOpacity(0.12),
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 10,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.orange : const Color(0xFF8C6040),
        )),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: _fillColor,
        selectedColor: AppColors.orange.withOpacity(0.12),
        labelStyle: const TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.w600),
        side: const BorderSide(color: _borderColor, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: AppColors.orange,
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: _borderColor, thickness: 1, space: 0,
      ),

      // ── SnackBar ─────────────────────────────────────────────────────────────
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

      // ── Dialog ───────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: _cardColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.orange.withOpacity(0.15), width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w900, color: _textMain, letterSpacing: -0.5,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14, color: _textSub, height: 1.6,
        ),
      ),

      // ── Bottom sheet ─────────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _cardColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: _cardColor,
        modalElevation: 0,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      // ── List tile ────────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Color(0xFFEEE8E3),
        iconColor: _textSub,
        textColor: _textMain,
        selectedColor: AppColors.orange,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // ── Icon ─────────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(color: _textSub, size: 22),

      // ── Tab bar ──────────────────────────────────────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.orange,
        unselectedLabelColor: Color(0xFF8C6040),
        indicatorColor: AppColors.orange,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5),
        dividerColor: _borderColor,
      ),

      // ── Floating action button ────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // ── Popup menu ───────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: _cardColor,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _borderColor, width: 1),
        ),
        textStyle: const TextStyle(color: _textMain, fontSize: 13, fontWeight: FontWeight.w500),
      ),

      // ── Tooltip ──────────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: _textMain,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Drawer ───────────────────────────────────────────────────────────────
      drawerTheme: const DrawerThemeData(
        backgroundColor: _cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    );
  }
}