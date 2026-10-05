import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rms/core/navigation/deep_link_handler.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/core/theme/theme_provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService().init();
  final initialDeepLink = await DeepLinkHandler.getInitialUriWithRetry();
  DeepLinkHandler.startListening();
  final prefs = await SharedPreferences.getInstance();
  final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MyApp(
        hasSeenOnboarding: hasSeenOnboarding,
        initialDeepLink: initialDeepLink,
      ),
    ),
  );
}
