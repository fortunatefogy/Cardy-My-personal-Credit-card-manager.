import 'package:flutter/material.dart';

final ValueNotifier<bool> cardyDarkMode = ValueNotifier(false);
final ValueNotifier<bool> biometricLockEnabled = ValueNotifier(true);

bool get isCardyDarkMode => cardyDarkMode.value;
Color get appBackground =>
    isCardyDarkMode ? const Color(0xFF101113) : const Color(0xFFF5F5F6);
Color get ink =>
    isCardyDarkMode ? const Color(0xFFF3F3F4) : const Color(0xFF171719);
Color get surface => isCardyDarkMode ? const Color(0xFF1C1D20) : Colors.white;
Color get brandAccent =>
    isCardyDarkMode ? const Color(0xFFF0F0F1) : const Color(0xFF171719);
Color get brandAccentDeep =>
    isCardyDarkMode ? const Color(0xFFD0D0D2) : const Color(0xFF303034);
Color get softSurface =>
    isCardyDarkMode ? const Color(0xFF292A2E) : const Color(0xFFF0F0F1);
Color get panelBorder =>
    isCardyDarkMode ? const Color(0xFF35363A) : const Color(0xFFE7E7E9);
Color get panelShadow =>
    isCardyDarkMode ? const Color(0x44000000) : const Color(0x18000000);
Color get bottomBarBackground =>
    isCardyDarkMode ? const Color(0xFF09090A) : const Color(0xFF171719);
Color get bottomBarSelected => Colors.white;
Color get bottomBarUnselected => const Color(0xFFBDBAC5);
Color get accentColor => brandAccent;
Color get muted =>
    isCardyDarkMode ? const Color(0xFFAAAAB0) : const Color(0xFF77777E);
