import 'package:flutter/material.dart';

final ValueNotifier<bool> cardyDarkMode = ValueNotifier(false);
final ValueNotifier<int> cardyColorThemeIndex = ValueNotifier(0);
final ValueNotifier<bool> biometricLockEnabled = ValueNotifier(true);

class CardyColorTheme {
  const CardyColorTheme({required this.name, required this.ramp});

  final String name;
  final List<Color> ramp;

  CardyColors colorsFor({required bool dark}) => dark ? _dark() : _light();

  CardyColors _light() {
    final c = ramp;
    return CardyColors(
      background: c[5],
      surface: c[6],
      softSurface: c[4],
      panelBorder: c[3],
      ink: _shade(c[0], .5),
      muted: _shade(c[1], .2),
      accent: c[0],
      onAccent: c[6],
      accentDeep: c[1],
      heroStart: _shade(c[0], .2),
      heroEnd: _shade(c[0], .5),
      bottomBar: _shade(c[0], .5),
      bottomBarSelected: c[6],
      bottomBarUnselected: c[2],
      stackBack: c[1],
      warningSurface: c[3],
      warningForeground: _shade(c[0], .5),
    );
  }

  CardyColors _dark() {
    final c = ramp;
    return CardyColors(
      background: _shade(c[0], .6),
      surface: _shade(c[0], .45),
      softSurface: _shade(c[0], .3),
      panelBorder: c[0],
      ink: c[6],
      muted: c[3],
      accent: c[5],
      onAccent: _shade(c[0], .6),
      accentDeep: c[3],
      heroStart: _shade(c[1], .45),
      heroEnd: _shade(c[0], .3),
      bottomBar: _shade(c[0], .75),
      bottomBarSelected: c[6],
      bottomBarUnselected: c[2],
      stackBack: _shade(c[0], .3),
      warningSurface: _shade(c[1], .65),
      warningForeground: c[5],
    );
  }

  static Color _shade(Color color, double amount) =>
      Color.lerp(color, Colors.black, amount)!;
}

class CardyColors {
  const CardyColors({
    required this.background,
    required this.surface,
    required this.softSurface,
    required this.panelBorder,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentDeep,
    required this.heroStart,
    required this.heroEnd,
    required this.bottomBar,
    required this.bottomBarSelected,
    required this.bottomBarUnselected,
    required this.stackBack,
    required this.warningSurface,
    required this.warningForeground,
  });

  final Color background;
  final Color surface;
  final Color softSurface;
  final Color panelBorder;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentDeep;
  final Color heroStart;
  final Color heroEnd;
  final Color bottomBar;
  final Color bottomBarSelected;
  final Color bottomBarUnselected;
  final Color stackBack;
  final Color warningSurface;
  final Color warningForeground;
}

const cardyColorThemes = [
  CardyColorTheme(name: 'Periwinkle', ramp: [
    Color(0xFF4D5A8F),
    Color(0xFF6D7CB0),
    Color(0xFF8F9DCC),
    Color(0xFFB3C0E6),
    Color(0xFFCED8F2),
    Color(0xFFE3EAFA),
    Color(0xFFF5F8FF),
  ]),
  CardyColorTheme(name: 'Pistachio', ramp: [
    Color(0xFF688F4D),
    Color(0xFF88B06D),
    Color(0xFFA6CC8F),
    Color(0xFFC6E6B3),
    Color(0xFFDBF2CE),
    Color(0xFFEBFAE3),
    Color(0xFFF8FFF5),
  ]),
  CardyColorTheme(name: 'Terracotta', ramp: [
    Color(0xFFA2533D),
    Color(0xFFC46F52),
    Color(0xFFD98D6F),
    Color(0xFFE7B79B),
    Color(0xFFF2D4BE),
    Color(0xFFFAE8D6),
    Color(0xFFFFF4E6),
  ]),
  CardyColorTheme(name: 'Ocean', ramp: [
    Color(0xFF29758E),
    Color(0xFF3699BA),
    Color(0xFF5DB3D0),
    Color(0xFF90CBDF),
    Color(0xFFB8DEEA),
    Color(0xFFDBEEF5),
    Color(0xFFF3F9FC),
  ]),
  CardyColorTheme(name: 'Plum', ramp: [
    Color(0xFF6F3E79),
    Color(0xFF91519E),
    Color(0xFFAD75B8),
    Color(0xFFC7A1CE),
    Color(0xFFDBC2E0),
    Color(0xFFEDE1EF),
    Color(0xFFF9F5FA),
  ]),
  CardyColorTheme(name: 'Rose', ramp: [
    Color(0xFF8E2943),
    Color(0xFFBA3657),
    Color(0xFFD05D7A),
    Color(0xFFDF90A4),
    Color(0xFFEAB8C4),
    Color(0xFFF5DBE2),
    Color(0xFFFCF3F5),
  ]),
  CardyColorTheme(name: 'Amber', ramp: [
    Color(0xFF9C6D1C),
    Color(0xFFCC8E24),
    Color(0xFFE0AA4D),
    Color(0xFFEAC586),
    Color(0xFFF1DAB1),
    Color(0xFFF8ECD8),
    Color(0xFFFDF9F2),
  ]),
  CardyColorTheme(name: 'Forest', ramp: [
    Color(0xFF3C7C51),
    Color(0xFF4EA26A),
    Color(0xFF72BB8A),
    Color(0xFF9FD1AF),
    Color(0xFFC1E1CC),
    Color(0xFFE0F0E5),
    Color(0xFFF5FAF6),
  ]),
  CardyColorTheme(name: 'Lavender', ramp: [
    Color(0xFF502E8A),
    Color(0xFF683CB4),
    Color(0xFF8962CB),
    Color(0xFFAE94DB),
    Color(0xFFCBBAE8),
    Color(0xFFE5DDF4),
    Color(0xFFF6F4FB),
  ]),
  CardyColorTheme(name: 'Mint', ramp: [
    Color(0xFF328570),
    Color(0xFF42AE93),
    Color(0xFF67C5AE),
    Color(0xFF97D8C8),
    Color(0xFFBCE6DB),
    Color(0xFFDEF2ED),
    Color(0xFFF4FBF9),
  ]),
  CardyColorTheme(name: 'Coral', ramp: [
    Color(0xFF973820),
    Color(0xFFC6492A),
    Color(0xFFDA6E52),
    Color(0xFFE69C89),
    Color(0xFFEFBFB3),
    Color(0xFFF7DFD9),
    Color(0xFFFCF4F2),
  ]),
  CardyColorTheme(name: 'Indigo', ramp: [
    Color(0xFF323E85),
    Color(0xFF4250AE),
    Color(0xFF6774C5),
    Color(0xFF97A0D8),
    Color(0xFFBCC2E6),
    Color(0xFFDEE0F2),
    Color(0xFFF4F5FB),
  ]),
  CardyColorTheme(name: 'Sand', ramp: [
    Color(0xFF816237),
    Color(0xFFA88048),
    Color(0xFFC09D6D),
    Color(0xFFD4BC9B),
    Color(0xFFE3D4BF),
    Color(0xFFF1EADF),
    Color(0xFFFAF8F4),
  ]),
  CardyColorTheme(name: 'Black & White', ramp: [
    Color(0xFF1F1F1F),
    Color(0xFF303030),
    Color(0xFF4A4A4A),
    Color(0xFF737373),
    Color(0xFFA3A3A3),
    Color(0xFFD4D4D4),
    Color(0xFFFFFFFF),
  ]),
  CardyColorTheme(name: 'White & Black', ramp: [
    Color(0xFF2B2622),
    Color(0xFF3F3934),
    Color(0xFF5C554E),
    Color(0xFF8A8379),
    Color(0xFFB3ACA2),
    Color(0xFFDCD6CC),
    Color(0xFFF7F4EE),
  ]),
];

bool get isCardyDarkMode => cardyDarkMode.value;
CardyColors get _colors => cardyColorThemes[cardyColorThemeIndex.value]
    .colorsFor(dark: isCardyDarkMode);
Color get appBackground => _colors.background;
Color get ink => _colors.ink;
Color get surface => _colors.surface;
Color get brandAccent => _colors.accent;
Color get brandAccentDeep => _colors.accentDeep;
Color get softSurface => _colors.softSurface;
Color get panelBorder => _colors.panelBorder;
Color get panelShadow =>
    isCardyDarkMode ? const Color(0x44000000) : const Color(0x18000000);
Color get bottomBarBackground => _colors.bottomBar;
Color get bottomBarSelected => _colors.bottomBarSelected;
Color get bottomBarUnselected => _colors.bottomBarUnselected;
Color get accentColor => _colors.accent;
Color get onAccent => _colors.onAccent;
Color get positiveColor =>
    isCardyDarkMode ? const Color(0xFF7DE0A1) : const Color(0xFF0B7A45);
Color get muted => _colors.muted;
Color get heroStart => _colors.heroStart;
Color get heroEnd => _colors.heroEnd;
Color get stackBack => _colors.stackBack;
Color get warningSurface => _colors.warningSurface;
Color get warningForeground => _colors.warningForeground;

ThemeData cardyThemeData(Brightness brightness) {
  final colors = cardyColorThemes[cardyColorThemeIndex.value]
      .colorsFor(dark: brightness == Brightness.dark);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onAccent,
    primaryContainer: colors.accent,
    onPrimaryContainer: colors.onAccent,
    secondary: colors.accentDeep,
    onSecondary: colors.onAccent,
    secondaryContainer: colors.softSurface,
    onSecondaryContainer: colors.ink,
    tertiary: colors.accentDeep,
    onTertiary: colors.onAccent,
    tertiaryContainer: colors.softSurface,
    onTertiaryContainer: colors.ink,
    error: Colors.redAccent,
    onError: Colors.white,
    errorContainer: colors.warningSurface,
    onErrorContainer: colors.warningForeground,
    surface: colors.surface,
    onSurface: colors.ink,
    onSurfaceVariant: colors.muted,
    surfaceContainerLowest: colors.background,
    surfaceContainerLow: colors.background,
    surfaceContainer: colors.surface,
    surfaceContainerHigh: colors.surface,
    surfaceContainerHighest: colors.softSurface,
    outline: colors.muted,
    outlineVariant: colors.panelBorder,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: colors.ink,
    onInverseSurface: colors.background,
    inversePrimary: colors.accentDeep,
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.background,
    colorScheme: scheme,
    fontFamily: cardyBodyFont,
    textTheme: _cardyTextTheme(brightness, colors.ink),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      titleTextStyle: TextStyle(
          fontFamily: cardyDisplayFont,
          color: colors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: colors.muted, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.surface),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      textStyle: TextStyle(color: colors.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.background),
      actionTextColor: colors.accentDeep,
    ),
    cardTheme: CardThemeData(
        color: colors.surface, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: colors.panelBorder),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accentDeep,
      selectionColor: colors.softSurface,
      selectionHandleColor: colors.accentDeep,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.ink,
      textColor: colors.ink,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: colors.background),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.panelBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.accentDeep, width: 1.4),
      ),
      hintStyle: TextStyle(color: colors.muted),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.onAccent,
    ),
    iconTheme: IconThemeData(color: colors.ink),
  );
}

const cardyDisplayFont = 'Fraunces';
const cardyBodyFont = 'DM Sans';

TextTheme _cardyTextTheme(Brightness brightness, Color ink) {
  final base = Typography.material2021(platform: TargetPlatform.android);
  final colored = (brightness == Brightness.dark ? base.white : base.black)
      .apply(fontFamily: cardyBodyFont, bodyColor: ink, displayColor: ink);
  TextStyle display(TextStyle? style) =>
      style!.copyWith(fontFamily: cardyDisplayFont);
  return colored.copyWith(
    displayLarge: display(colored.displayLarge),
    displayMedium: display(colored.displayMedium),
    displaySmall: display(colored.displaySmall),
    headlineLarge: display(colored.headlineLarge),
    headlineMedium: display(colored.headlineMedium),
    headlineSmall: display(colored.headlineSmall),
    titleLarge: display(colored.titleLarge),
  );
}
