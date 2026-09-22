  // lib/screens/admin_theme.dart
  import 'package:flutter/material.dart';

  class AdminTheme {
    // ══════════════════════════════════════════════════════════════
    // LIGHT MODE COLORS
    // ══════════════════════════════════════════════════════════════
    static const Color orange      = Color(0xFFE8994A);
    static const Color orangeLight = Color(0xFFFFF4E6);
    static const Color orangeText  = Color(0xFFA05A00);
    static const Color dark        = Color(0xFF1C1C1A);
    static const Color dark2       = Color(0xFF2A2A28);
    static const Color body        = Color(0xFFF5F4F0);
    static const Color white       = Color(0xFFFFFFFF);
    static const Color border      = Color(0xFFE8E6E0);
    static const Color borderLight = Color(0xFFEEEDE8);
    static const Color surface     = Color(0xFFFAFAFB);
    static const Color muted       = Color(0xFF999999);
    static const Color text        = Color(0xFF1A1A18);
    static const Color textMuted   = Color(0xFF888888);
    static const Color green       = Color(0xFF1A7A45);
    static const Color greenLight  = Color(0xFFE8F9F0);
    static const Color red         = Color(0xFFA02020);
    static const Color redLight    = Color(0xFFFEEAEA);
    static const Color blue        = Color(0xFF1A4FAA);
    static const Color blueLight   = Color(0xFFE8F0FE);
    static const Color grayAvatar  = Color(0xFFF0EFEA);
    static const Color grayText    = Color(0xFF555555);

    // ── Light mode: NAV & HEADER specific ──
    static const Color lightNavBg          = Color(0xFFFFFFFF);  // white sidebar
    static const Color lightTopBarBg       = Color(0xFFFFFFFF);  // white topbar
    static const Color lightNavBorder      = Color(0xFFD8D8D8);
    static const Color lightNavText        = Color(0xFF53433C);  // warm brown
    static const Color lightSidebarLogoBox = Color(0xFFFFB77D);  // soft salmon
    static const Color lightSidebarBrand   = Color(0xFFFF8C00);  // bright orange
    static const Color lightClockCardBg    = Color(0xFFEBEBEB);
    static const Color lightClockCardText  = Color(0xFF333333);
    static const Color lightClockDotColor  = Color(0xFF008A00);

    // ── Light mode accents ──
    static const Color lightAccent   = Color(0xFFE8994A);
    static const Color lightElevated = Color(0xFFF1EEEA);

    // ══════════════════════════════════════════════════════════════
    // DARK MODE COLORS
    // ══════════════════════════════════════════════════════════════
    static const Color darkBg         = Color(0xFF000000);
    static const Color darkCard       = Color(0xFF121212);
    static const Color darkSurface    = Color(0xFF241912);
    static const Color darkElevated   = Color(0xFF3F3229);
    static const Color darkBorder     = Color(0xFF2C2C2E);
    static const Color darkBorderWarm = Color(0xFF564334);
    static const Color darkText       = Color(0xFFF3DFD1);
    static const Color darkTextMuted  = Color(0xFFDDC1AE);
    static const Color darkMuted      = Color(0xFF6B7280);

    // ── Dark mode: NAV & HEADER specific ──
    static const Color darkNavBg          = Color(0xFF281D15);  // warm brown sidebar
    static const Color darkTopBarBg       = Color(0xFF1B110A);  // darker warm brown topbar
    static const Color darkNavBorder      = Color(0xFF564334);
    static const Color darkNavText        = Color(0xFFDDC1AE);  // tan
    static const Color darkSidebarLogoBox = Color(0xFFFF8C00);  // bright orange
    static const Color darkSidebarBrand   = Color(0xFFFFB77D);  // soft salmon
    static const Color darkClockCardBg    = Color(0xFF3F3229);
    static const Color darkClockCardText  = Color(0xFFFFB77D);
    static const Color darkClockDotColor  = Color(0xFF4CE346);

    // ── Dark mode accents ──
    static const Color darkOrangeBright = Color(0xFFFF8C00);
    static const Color darkOrangeSoft   = Color(0xFFFFB77D);
    static const Color darkOrangeDeep   = Color(0xFF623200);
    static const Color darkGreenBright  = Color(0xFF4CE346);
    static const Color darkRedSoft      = Color(0xFFFFB4AB);

    // ══════════════════════════════════════════════════════════════
    // SPACING & RADIUS
    // ══════════════════════════════════════════════════════════════
    static const double s1 = 4;
    static const double s2 = 8;
    static const double s3 = 12;
    static const double s4 = 16;
    static const double s5 = 20;
    static const double s6 = 24;

    static const double radiusSm   = 6;
    static const double radius     = 8;
    static const double radiusMd   = 10;
    static const double radiusLg   = 12;
    static const double radiusPill = 20;

    static const double textXS   = 10;
    static const double textSm   = 11;
    static const double textBase = 12.5;
    static const double textMd   = 13;
    static const double textLg   = 14;
    static const double textXl   = 20;
    static const double text2xl  = 26;

    // ══════════════════════════════════════════════════════════════
    // ACCESSOR
    // ══════════════════════════════════════════════════════════════
    static AdminColors getColors(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return isDark ? darkColors : lightColors;
    }

    // ══════════════════════════════════════════════════════════════
    // LIGHT COLOR BUNDLE
    // ══════════════════════════════════════════════════════════════
    static const AdminColors lightColors = AdminColors(
      isDark: false,
      background: body,
      card: white,
      surface: surface,
      elevated: lightElevated,
      border: border,
      borderWarm: border,
      text: text,
      textMuted: textMuted,
      muted: muted,
      // ── Nav & Topbar ──
      navBg: lightNavBg,
      topBarBg: lightTopBarBg,
      navBorder: lightNavBorder,
      navText: lightNavText,
      sidebarLogoBox: lightSidebarLogoBox,
      sidebarBrandText: lightSidebarBrand,
      sidebarActiveText: Colors.white,
      clockCardBg: lightClockCardBg,
      clockCardText: lightClockCardText,
      clockDotColor: lightClockDotColor,
      // ── Rest ──
      orange: orange,
      orangeLight: orangeLight,
      orangeText: orangeText,
      accent: lightAccent,
      green: green,
      greenLight: greenLight,
      red: red,
      redLight: redLight,
      blue: blue,
      blueLight: blueLight,
      grayAvatar: grayAvatar,
      grayText: grayText,
      onOrange: Colors.white,
    );

    // ══════════════════════════════════════════════════════════════
    // DARK COLOR BUNDLE
    // ══════════════════════════════════════════════════════════════
    static const AdminColors darkColors = AdminColors(
      isDark: true,
      background: darkBg,
      card: darkCard,
      surface: darkSurface,
      elevated: darkElevated,
      border: darkBorder,
      borderWarm: darkBorderWarm,
      text: darkText,
      textMuted: darkTextMuted,
      muted: darkMuted,
      // ── Nav & Topbar ──
      navBg: darkNavBg,
      topBarBg: darkTopBarBg,
      navBorder: darkNavBorder,
      navText: darkNavText,
      sidebarLogoBox: darkSidebarLogoBox,
      sidebarBrandText: darkSidebarBrand,
      sidebarActiveText: Colors.white,
      clockCardBg: darkClockCardBg,
      clockCardText: darkClockCardText,
      clockDotColor: darkClockDotColor,
      // ── Rest ──
      orange: darkOrangeBright,
      orangeLight: darkOrangeSoft,
      orangeText: darkOrangeDeep,
      accent: darkOrangeSoft,
      green: darkGreenBright,
      greenLight: Color(0xFF14361F),
      red: darkRedSoft,
      redLight: Color(0xFF3B1212),
      blue: Color(0xFF93C5FD),
      blueLight: Color(0xFF1E293B),
      grayAvatar: darkElevated,
      grayText: darkTextMuted,
      onOrange: darkOrangeDeep,
    );

    static ThemeData themeData(bool isDark) {
      final base = isDark ? darkColors : lightColors;
      return ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        useMaterial3: true,
        primaryColor: base.orange,
        scaffoldBackgroundColor: base.background,
        cardColor: base.card,
        canvasColor: base.card,
        dividerColor: base.border,
        iconTheme: IconThemeData(color: base.text),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: base.text),
          bodyMedium: TextStyle(color: base.text),
          titleLarge: TextStyle(color: base.text),
          titleMedium: TextStyle(color: base.text),
        ),
        colorScheme: ColorScheme(
          brightness: isDark ? Brightness.dark : Brightness.light,
          primary: base.orange,
          onPrimary: Colors.white,
          secondary: base.orange,
          onSecondary: Colors.white,
          error: base.red,
          onError: Colors.white,
          surface: base.surface,
          onSurface: base.text,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: base.card,
          titleTextStyle: TextStyle(
            color: base.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: TextStyle(color: base.text),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(base.card),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(color: base.card),
        appBarTheme: AppBarTheme(
          backgroundColor: base.topBarBg,
          foregroundColor: base.accent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════
  class AdminColors {
    final bool isDark;

    // Core surfaces
    final Color background;
    final Color card;
    final Color surface;
    final Color elevated;
    final Color border;
    final Color borderWarm;
    final Color text;
    final Color textMuted;
    final Color muted;

    // Nav & Topbar
    final Color navBg;
    final Color topBarBg;
    final Color navBorder;
    final Color navText;
    final Color sidebarLogoBox;
    final Color sidebarBrandText;
    final Color sidebarActiveText;
    final Color clockCardBg;
    final Color clockCardText;
    final Color clockDotColor;

    // Accents
    final Color orange;
    final Color orangeLight;
    final Color orangeText;
    final Color accent;
    final Color green;
    final Color greenLight;
    final Color red;
    final Color redLight;
    final Color blue;
    final Color blueLight;
    final Color grayAvatar;
    final Color grayText;
    final Color onOrange;

    const AdminColors({
      required this.isDark,
      required this.background,
      required this.card,
      required this.surface,
      required this.elevated,
      required this.border,
      required this.borderWarm,
      required this.text,
      required this.textMuted,
      required this.muted,
      required this.navBg,
      required this.topBarBg,
      required this.navBorder,
      required this.navText,
      required this.sidebarLogoBox,
      required this.sidebarBrandText,
      required this.sidebarActiveText,
      required this.clockCardBg,
      required this.clockCardText,
      required this.clockDotColor,
      required this.orange,
      required this.orangeLight,
      required this.orangeText,
      required this.accent,
      required this.green,
      required this.greenLight,
      required this.red,
      required this.redLight,
      required this.blue,
      required this.blueLight,
      required this.grayAvatar,
      required this.grayText,
      required this.onOrange,
    });

    // Pills
    Color get pillGreenBg =>
        isDark ? const Color(0xFF14361F) : const Color(0xFFDCFCE7);
    Color get pillGreenTx =>
        isDark ? const Color(0xFF4CE346) : const Color(0xFF166534);
    Color get pillWarnBg =>
        isDark ? const Color(0xFF3A2A0F) : const Color(0xFFFEF3C7);
    Color get pillWarnTx =>
        isDark ? const Color(0xFFFFB77D) : const Color(0xFF92400E);
    Color get pillBlueBg =>
        isDark ? const Color(0xFF1E293B) : const Color(0xFFDBEAFE);
    Color get pillBlueTx =>
        isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF);
    Color get pillErrBg =>
        isDark ? const Color(0xFF3B1212) : const Color(0xFFFEE2E2);
    Color get pillErrTx =>
        isDark ? const Color(0xFFFFB4AB) : const Color(0xFFDC2626);
  }

  // ══════════════════════════════════════════════════════════════════
  class ThemeProvider extends ChangeNotifier {
    ThemeProvider._();
    static final ThemeProvider instance = ThemeProvider._();

    bool _isDark = false;
    bool get isDark => _isDark;

    void toggleDarkMode() {
      _isDark = !_isDark;
      notifyListeners();
    }

    void setDarkMode(bool dark) {
      if (_isDark != dark) {
        _isDark = dark;
        notifyListeners();
      }
    }

    ThemeData get theme => AdminTheme.themeData(_isDark);
    AdminColors get colors =>
        _isDark ? AdminTheme.darkColors : AdminTheme.lightColors;
  }

  Route<T> adminRoute<T>(Widget page) {
    return MaterialPageRoute<T>(
      builder: (_) => AnimatedBuilder(
        animation: ThemeProvider.instance,
        builder: (_, __) => Theme(
          data: ThemeProvider.instance.theme,
          child: page,
        ),
      ),
    );
  }