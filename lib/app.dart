import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/features/auth/auth_guard.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/features/auth/reset_password_page.dart';
import 'package:rms/features/home/main_navigation.dart';
import 'package:rms/features/login/login.dart';
import 'package:rms/features/onboarding/onboarding_view.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/core/l10n/locale_provider.dart';
import 'core/navigation/app_navigator.dart';
import 'core/navigation/deep_link_handler.dart';
import 'core/theme/theme_provider.dart';

class MyApp extends ConsumerWidget {
  final bool hasSeenOnboarding;
  final Uri? initialDeepLink;

  const MyApp({
    super.key,
    this.hasSeenOnboarding = false,
    this.initialDeepLink,
  });

  String _resolveInitialRoute({Uri? deepLink}) {
    final resetRoute = DeepLinkHandler.initialRouteForDeepLink(
      deepLink,
      fallbackPath: deepLink?.path ?? Uri.base.path,
    );
    if (resetRoute != null) {
      return resetRoute;
    }

    if (AuthService().isAuthenticated) {
      if (!hasSeenOnboarding) {
        return '/onboarding';
      }
      return '/home';
    }

    if (!hasSeenOnboarding) {
      return '/onboarding';
    }

    return '/login';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(usernameProvider, (previous, next) {
      if (previous != next) {
        ref.read(themeProvider.notifier).refreshForUser();
      }
    });

    // Escuchar el tema y actualizar FeedPalette
    final currentTheme = ref.watch(themeProvider);
    FeedPalette.update(currentTheme);
    final appLocale = ref.watch(appLocaleProvider);

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      builder: (context, child) => DeepLinkBootstrap(
        initialDeepLink: initialDeepLink,
        child: child ?? const SizedBox.shrink(),
      ),
      title: 'FitConnect',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        FitconnectLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
      ],
      locale: appLocale,
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return const Locale('en');
        if (locale.languageCode.startsWith('es')) return const Locale('es');
        return const Locale('en');
      },
      theme: _buildTheme(currentTheme),
      initialRoute: _resolveInitialRoute(deepLink: initialDeepLink),
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '/login';
        final resetUri = DeepLinkHandler.parseRouteUri(routeName);
        if (resetUri != null) {
          return MaterialPageRoute(
            builder: (_) => ResetPasswordPage(
              initialToken: DeepLinkHandler.extractToken(resetUri),
            ),
            settings: settings,
          );
        }

        final uri = Uri.tryParse(routeName) ?? Uri(path: routeName);
        if (uri.path == '/reset-password' || uri.host == 'reset-password') {
          return MaterialPageRoute(
            builder: (_) => ResetPasswordPage(
              initialToken: DeepLinkHandler.extractToken(uri),
            ),
            settings: settings,
          );
        }

        if (uri.path == '/home') {
          return MaterialPageRoute(
            builder: (_) => const AuthGuard(child: MainNavigationScreen()),
            settings: settings,
          );
        }

        if (uri.path == '/onboarding') {
          return MaterialPageRoute(
            builder: (_) => const OnboardingView(),
            settings: settings,
          );
        }

        return MaterialPageRoute(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      },
    );
  }
}

ThemeData _buildTheme(AppThemeState theme) {
  final isDark = theme.isDarkMode;
  final base = isDark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final colorScheme = ColorScheme(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primary: theme.accent,
    onPrimary: Colors.white,
    secondary: theme.accent,
    onSecondary: Colors.white,
    surface: theme.surface,
    onSurface: theme.text,
    onSurfaceVariant: theme.muted,
    surfaceContainerHighest: theme.surfaceSoft,
    outline: theme.border,
    error: Colors.red,
    onError: Colors.white,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: theme.text,
    displayColor: theme.text,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    primaryColor: theme.accent,
    scaffoldBackgroundColor: theme.background,
    canvasColor: theme.background,
    cardColor: theme.surface,
    dividerColor: theme.border,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: theme.background,
      foregroundColor: theme.text,
      elevation: 0,
      iconTheme: IconThemeData(color: theme.text),
    ),
    iconTheme: IconThemeData(color: theme.text),
    primaryIconTheme: IconThemeData(color: theme.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: theme.surfaceSoft,
      hintStyle: TextStyle(color: theme.muted, fontSize: 14),
      labelStyle: TextStyle(color: theme.muted),
      floatingLabelStyle: TextStyle(color: theme.accent),
      prefixIconColor: theme.muted,
      suffixIconColor: theme.muted,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(theme.surfaceSoft),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      hintStyle: WidgetStatePropertyAll(TextStyle(color: theme.muted)),
      textStyle: WidgetStatePropertyAll(TextStyle(color: theme.text)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: theme.surfaceSoft,
      disabledColor: theme.surface,
      selectedColor: theme.accent.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: theme.text),
      secondaryLabelStyle: TextStyle(color: theme.muted),
      side: BorderSide(color: theme.border),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: theme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: theme.text,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: theme.text, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: theme.surface,
      contentTextStyle: TextStyle(color: theme.text),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return theme.accent;
        return theme.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return theme.accent.withValues(alpha: 0.45);
        }
        return theme.border;
      }),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: theme.surface,
      modalBackgroundColor: theme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: theme.accent,
      unselectedLabelColor: theme.muted,
      indicatorColor: theme.accent,
      dividerColor: theme.border,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: theme.text,
      textColor: theme.text,
      titleTextStyle: TextStyle(color: theme.text),
      subtitleTextStyle: TextStyle(color: theme.muted),
    ),
  );
}
