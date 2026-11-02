import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/cardy_palette.dart';

class ThemesPage extends StatelessWidget {
  const ThemesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Themes')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: cardyDarkMode,
                builder: (context, darkMode, child) => SwitchListTile(
                  title: const Text('Dark mode'),
                  subtitle: const Text('Use a darker theme throughout Cardy.'),
                  secondary: HugeIcon(
                      icon: darkMode
                          ? HugeIcons.strokeRoundedMoon01
                          : HugeIcons.strokeRoundedSun01),
                  value: darkMode,
                  onChanged: (value) async {
                    cardyDarkMode.value = value;
                    final preferences = await SharedPreferences.getInstance();
                    await preferences.setBool('dark_mode', value);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  'COLOR THEME',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              for (var index = 0; index < cardyColorThemes.length; index++)
                _ThemeTile(index: index),
            ],
          ),
        ),
      );
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = cardyColorThemes[index];
    return ValueListenableBuilder<int>(
      valueListenable: cardyColorThemeIndex,
      builder: (context, selected, child) => ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final color in theme.ramp)
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: panelBorder),
                ),
              ),
          ],
        ),
        title: Text(theme.name),
        trailing: selected == index
            ? Icon(Icons.check_rounded, color: brandAccent)
            : null,
        onTap: () async {
          cardyColorThemeIndex.value = index;
          final preferences = await SharedPreferences.getInstance();
          await preferences.setInt('color_theme', index);
        },
      ),
    );
  }
}
