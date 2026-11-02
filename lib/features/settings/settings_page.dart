import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/cardy_palette.dart';
import '../../theme/cardy_transitions.dart';
import 'themes_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading:
                    const HugeIcon(icon: HugeIcons.strokeRoundedPaintBoard),
                title: const Text('Themes'),
                subtitle: ListenableBuilder(
                  listenable:
                      Listenable.merge([cardyColorThemeIndex, cardyDarkMode]),
                  builder: (context, child) => Text(
                      '${cardyColorThemes[cardyColorThemeIndex.value].name} · ${cardyDarkMode.value ? 'Dark' : 'Light'}'),
                ),
                trailing:
                    const HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01),
                onTap: () => Navigator.of(context).push<void>(
                  cardyPageRoute<void>((_) => const ThemesPage()),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: biometricLockEnabled,
                builder: (context, enabled, child) => SwitchListTile(
                  title: const Text('Biometric lock'),
                  subtitle: const Text(
                      'Require fingerprint, face or screen lock to open Cardy.'),
                  secondary:
                      const HugeIcon(icon: HugeIcons.strokeRoundedFingerPrint),
                  value: enabled,
                  onChanged: (value) async {
                    biometricLockEnabled.value = value;
                    final preferences = await SharedPreferences.getInstance();
                    await preferences.setBool('biometric_lock', value);
                  },
                ),
              ),
            ],
          ),
        ),
      );
}
