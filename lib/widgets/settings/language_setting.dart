import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'settings_card.dart';
import 'settings_item.dart';

class LanguageSetting extends StatelessWidget {
  const LanguageSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      child: SettingsItem(
        title: 'Language',
        icon: Icons.language,
        subtitle: 'Choose your preferred language',
        control: DropdownButton<Locale?>(
          value: context.locale,
          items: [
            DropdownMenuItem(
              value: null,
              child: Text('System Default').tr(),
            ),
            ...context.supportedLocales.map((locale) {
              return DropdownMenuItem(
                value: locale,
                child: Text(locale.toLanguageTag()),
              );
            }),
          ],
          onChanged: (Locale? locale) {
            if (locale == null) {
              context.resetLocale();
              return;
            }
            context.setLocale(locale);
          },
        ),
      ),
    );
  }
}
