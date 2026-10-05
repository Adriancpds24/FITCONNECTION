import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_provider.dart';

class AppLocaleNotifier extends Notifier<Locale?> {
  static const _localeKey = 'app_locale'; // 'es' | 'en' | null (system)

  @override
  Locale? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final code = prefs.getString(_localeKey);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  void useSystem() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.remove(_localeKey);
    state = null;
  }

  void setLocale(Locale locale) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_localeKey, locale.languageCode);
    state = Locale(locale.languageCode);
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleNotifier, Locale?>(
  AppLocaleNotifier.new,
);
