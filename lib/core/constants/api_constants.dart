import 'package:flutter/foundation.dart';

class ApiConstants {
  static String get apiHost {
    const defined = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (defined.isNotEmpty) return defined;

    if (kIsWeb) {
      final base = Uri.base;
      final isLocal = base.host == 'localhost' ||
          base.host == '127.0.0.1' ||
          base.host == '0.0.0.0';

      // Local dev: Flutter web is usually served on :8081 and API on :3000.
      if (isLocal) {
        final scheme = base.scheme.isEmpty ? 'http' : base.scheme;
        return '$scheme://localhost:3000/api';
      }

      // Production: serve the API under the same domain at `/api`.
      return '${base.origin}/api';
    }

    throw StateError(
      'API_BASE_URL no está configurada. Define --dart-define=API_BASE_URL=https://tu-dominio.com/api',
    );
  }

  static String get baseUrl => '$apiHost/auth';
  static String get authBaseUrl => '$apiHost/auth';
  static String get adminBaseUrl => '$apiHost/admin';
  static String get socialBaseUrl => '$apiHost/social';
  static String get trainingBaseUrl => '$apiHost/training';
  static String get nutritionBaseUrl => '$apiHost/nutrition';
  static String get progressBaseUrl => '$apiHost/progress';
}
