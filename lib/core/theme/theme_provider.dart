import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/auth_service.dart';

enum AppThemeType { orange, green, blue }

class AppThemeState {
  final AppThemeType type;
  final bool isDarkMode;
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color accent;
  final Color text;
  final Color muted;
  final Color border;
  final LinearGradient screenGradient;
  final LinearGradient heroGradient;
  final LinearGradient storyGradient;

  AppThemeState({
    required this.type,
    this.isDarkMode = false,
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.accent,
    required this.text,
    required this.muted,
    required this.border,
    required this.screenGradient,
    required this.heroGradient,
    required this.storyGradient,
  });

  static AppThemeState orange({bool isDark = false}) => AppThemeState(
        type: AppThemeType.orange,
        isDarkMode: isDark,
        background: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF7F1EA),
        surface: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFBF6),
        surfaceSoft: isDark ? const Color(0xFF242424) : const Color(0xFFFFF4EB),
        accent: const Color(0xFFFF6A2B),
        text: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF241A14),
        muted: isDark ? const Color(0xFFB0B0B0) : const Color(0xFF7D6A5C),
        border: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEBDDCF),
        screenGradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF161616), const Color(0xFF0F0F0F)]
              : [const Color(0xFFFFF8F1), const Color(0xFFF7F1EA)],
        ),
        heroGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF242424),
                  const Color(0xFF1A1A1A),
                  const Color(0xFF121212)
                ]
              : [
                  const Color(0xFFFFE9DA),
                  const Color(0xFFFCD7C1),
                  const Color(0xFFFFF4EB)
                ],
        ),
        storyGradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFF9D00), Color(0xFFFF4D00), Color(0xFFFF1900)],
        ),
      );

  static AppThemeState green({bool isDark = false}) => AppThemeState(
        type: AppThemeType.green,
        isDarkMode: isDark,
        background: isDark ? const Color(0xFF0A100D) : const Color(0xFFF0FDF4),
        surface: isDark ? const Color(0xFF121A16) : const Color(0xFFFFFFFF),
        surfaceSoft: isDark ? const Color(0xFF1B2620) : const Color(0xFFDCFCE7),
        accent: const Color(0xFF22C55E),
        text: isDark ? const Color(0xFFF0FDF4) : const Color(0xFF064E3B),
        muted: isDark ? const Color(0xFF86EFAC) : const Color(0xFF3F6212),
        border: isDark ? const Color(0xFF1B2620) : const Color(0xFFBBF7D0),
        screenGradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF121A16), const Color(0xFF0A100D)]
              : [const Color(0xFFF0FDF4), const Color(0xFFFFFFFF)],
        ),
        heroGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1B2620),
                  const Color(0xFF121A16),
                  const Color(0xFF0A100D)
                ]
              : [
                  const Color(0xFFBBF7D0),
                  const Color(0xFF86EFAC),
                  const Color(0xFFF0FDF4)
                ],
        ),
        storyGradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF4ADE80), Color(0xFF22C55E), Color(0xFF16A34A)],
        ),
      );

  static AppThemeState blue({bool isDark = false}) => AppThemeState(
        type: AppThemeType.blue,
        isDarkMode: isDark,
        background: isDark ? const Color(0xFF0A0F12) : const Color(0xFFF0F9FF),
        surface: isDark ? const Color(0xFF12181C) : const Color(0xFFFFFFFF),
        surfaceSoft: isDark ? const Color(0xFF1B242A) : const Color(0xFFE0F2FE),
        accent: const Color(0xFF0EA5E9),
        text: isDark ? const Color(0xFFF0F9FF) : const Color(0xFF0C4A6E),
        muted: isDark
            ? const Color(0xFF7DD3FC).withValues(alpha: 0.7)
            : const Color(0xFF075985),
        border: isDark ? const Color(0xFF1B242A) : const Color(0xFFBAE6FD),
        screenGradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF12181C), const Color(0xFF0A0F12)]
              : [const Color(0xFFF0F9FF), const Color(0xFFFFFFFF)],
        ),
        heroGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1B242A),
                  const Color(0xFF12181C),
                  const Color(0xFF0A0F12)
                ]
              : [
                  const Color(0xFFBAE6FD),
                  const Color(0xFF7DD3FC),
                  const Color(0xFFF0F9FF)
                ],
        ),
        storyGradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9), Color(0xFF0284C7)],
        ),
      );
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class AppThemeNotifier extends Notifier<AppThemeState> {
  static const themeKey = 'app_theme_type';
  static const darkModeKey = 'app_dark_mode';
  static const lastThemeUserKey = 'app_theme_last_user';

  static const _themeKey = themeKey;
  static const _darkModeKey = darkModeKey;
  static const _lastThemeUserKey = lastThemeUserKey;

  @override
  AppThemeState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final username = ref.watch(usernameProvider);
    final themeUserKey = (username != null && username.isNotEmpty)
        ? username
        : (prefs.getString(_lastThemeUserKey) ?? 'guest');

    final savedThemeStr =
        prefs.getString('${_themeKey}_$themeUserKey') ?? 'orange';
    final savedDarkMode =
        prefs.getBool('${_darkModeKey}_$themeUserKey') ?? false;

    AppThemeType savedType;
    switch (savedThemeStr) {
      case 'green':
        savedType = AppThemeType.green;
        break;
      case 'blue':
        savedType = AppThemeType.blue;
        break;
      case 'orange':
      default:
        savedType = AppThemeType.orange;
        break;
    }

    return _getStateForType(savedType, savedDarkMode);
  }

  void refreshForUser() {
    state = build();
  }

  AppThemeState _getStateForType(AppThemeType type, bool isDark) {
    switch (type) {
      case AppThemeType.orange:
        return AppThemeState.orange(isDark: isDark);
      case AppThemeType.green:
        return AppThemeState.green(isDark: isDark);
      case AppThemeType.blue:
        return AppThemeState.blue(isDark: isDark);
    }
  }

  void setTheme(AppThemeType type) {
    final isDark = state.isDarkMode;
    state = _getStateForType(type, isDark);
    _saveTheme(type, isDark);
  }

  void toggleDarkMode() {
    final isDark = !state.isDarkMode;
    state = _getStateForType(state.type, isDark);
    _saveTheme(state.type, isDark);
  }

  void _saveTheme(AppThemeType type, bool isDark) {
    final prefs = ref.read(sharedPreferencesProvider);
    final username = prefs.getString('auth_username') ?? 'guest';
    prefs.setString('${_themeKey}_$username', type.name);
    prefs.setBool('${_darkModeKey}_$username', isDark);
    if (username.isNotEmpty && username != 'guest') {
      prefs.setString(_lastThemeUserKey, username);
    }
  }
}

final themeProvider = NotifierProvider<AppThemeNotifier, AppThemeState>(() {
  return AppThemeNotifier();
});
