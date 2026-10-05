import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_navigator.dart';

class DeepLinkHandler {
  DeepLinkHandler._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static bool _handledInitialPasswordReset = false;

  /// Lee el enlace con reintentos (iOS/Android a veces lo entregan tarde).
  static Future<Uri?> getInitialUriWithRetry({
    int attempts = 4,
    Duration delay = const Duration(milliseconds: 120),
  }) async {
    if (kIsWeb) return null;

    Uri? uri;
    for (var i = 0; i < attempts; i++) {
      try {
        uri = await _appLinks.getInitialLink();
      } catch (e) {
        debugPrint('DeepLinkHandler.getInitialUriWithRetry: $e');
      }
      if (uri != null && uri.toString().isNotEmpty) {
        return uri;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(delay);
      }
    }
    return null;
  }

  static void startListening() {
    if (kIsWeb) return;
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      _openUri,
      onError: (error) => debugPrint('DeepLinkHandler stream: $error'),
    );
  }

  static bool isPasswordResetLink(Uri uri) {
    final path = uri.path.toLowerCase();
    final host = uri.host.toLowerCase();
    final full = uri.toString().toLowerCase();
    return path.contains('reset-password') ||
        host == 'reset-password' ||
        host.endsWith('reset-password') ||
        full.contains('reset-password');
  }

  static String? extractToken(Uri uri) {
    final fromQuery = uri.queryParameters['token']?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }

    if (uri.fragment.isNotEmpty) {
      final fragmentUri = Uri.tryParse('?${uri.fragment}');
      final fromFragment = fragmentUri?.queryParameters['token']?.trim();
      if (fromFragment != null && fromFragment.isNotEmpty) {
        return fromFragment;
      }
    }

    return null;
  }

  static Uri? parseRouteUri(String? routeName) {
    if (routeName == null || routeName.isEmpty) return null;

    final direct = Uri.tryParse(routeName);
    if (direct != null && isPasswordResetLink(direct)) {
      return direct;
    }

    if (routeName.contains('reset-password')) {
      final withScheme =
          routeName.contains('://') ? routeName : 'fitconnect://$routeName';
      final parsed = Uri.tryParse(withScheme);
      if (parsed != null && isPasswordResetLink(parsed)) {
        return parsed;
      }
    }

    return null;
  }

  static String routeForPasswordReset(Uri uri) {
    final token = extractToken(uri);
    if (token != null && token.isNotEmpty) {
      return '/reset-password?token=$token';
    }
    return '/reset-password';
  }

  static String? initialRouteForDeepLink(Uri? deepLink,
      {String fallbackPath = ''}) {
    if (deepLink != null && isPasswordResetLink(deepLink)) {
      return routeForPasswordReset(deepLink);
    }

    final path = fallbackPath.isNotEmpty ? fallbackPath : Uri.base.path;
    if (path.toLowerCase().contains('reset-password')) {
      final token = Uri.base.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        return '/reset-password?token=$token';
      }
      return '/reset-password';
    }

    return null;
  }

  static void navigateToPasswordReset(Uri uri) {
    final route = routeForPasswordReset(uri);
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      debugPrint('DeepLinkHandler: navigator not ready for $route');
      return;
    }
    nav.pushNamedAndRemoveUntil(route, (route) => false);
  }

  static void _openUri(Uri uri) {
    if (isPasswordResetLink(uri)) {
      navigateToPasswordReset(uri);
    }
  }

  /// Si el enlace llegó después del arranque, fuerza ir a restablecer contraseña.
  static Future<void> ensurePasswordResetHandled(Uri? initialDeepLink) async {
    if (_handledInitialPasswordReset) return;

    Uri? uri = initialDeepLink;
    uri ??= await getInitialUriWithRetry(
        attempts: 2, delay: const Duration(milliseconds: 80));

    if (uri == null || !isPasswordResetLink(uri)) return;

    _handledInitialPasswordReset = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigateToPasswordReset(uri!);
    });
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Comprueba de nuevo el deep link tras el primer frame (enlaces que llegan tarde).
class DeepLinkBootstrap extends StatefulWidget {
  final Widget child;
  final Uri? initialDeepLink;

  const DeepLinkBootstrap({
    super.key,
    required this.child,
    this.initialDeepLink,
  });

  @override
  State<DeepLinkBootstrap> createState() => _DeepLinkBootstrapState();
}

class _DeepLinkBootstrapState extends State<DeepLinkBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkHandler.ensurePasswordResetHandled(widget.initialDeepLink);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
