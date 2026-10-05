import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rms/features/auth/auth_service.dart';

class HttpRetry {
  static bool _signingOut = false;

  static Future<void> _maybeSignOutOnAuthError(http.Response response) async {
    if (_signingOut) return;
    if (!AuthService().isAuthenticated) return;
    if (response.statusCode != 401 && response.statusCode != 403) return;

    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['error'] is String) {
        final error = (decoded['error'] as String).toLowerCase();
        final looksLikeAuthFailure = error.contains('token invalido') ||
            error.contains('token inválido') ||
            error.contains('expirado') ||
            error.contains('acceso denegado') ||
            error.contains('no proporcionado') ||
            error.contains('no encontrado');

        if (!looksLikeAuthFailure) return;
      } else {
        return;
      }
    } catch (_) {
      return;
    }

    _signingOut = true;
    try {
      await AuthService().signOut();
    } finally {
      _signingOut = false;
    }
  }

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    int retries = 2,
    Duration backoff = const Duration(milliseconds: 250),
  }) async {
    return _run(
      () => http.get(url, headers: headers).timeout(timeout),
      retries: retries,
      backoff: backoff,
    );
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 10),
    int retries = 2,
    Duration backoff = const Duration(milliseconds: 250),
  }) async {
    return _run(
      () => http
          .post(url, headers: headers, body: body, encoding: encoding)
          .timeout(timeout),
      retries: retries,
      backoff: backoff,
    );
  }

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 10),
    int retries = 2,
    Duration backoff = const Duration(milliseconds: 250),
  }) async {
    return _run(
      () => http
          .put(url, headers: headers, body: body, encoding: encoding)
          .timeout(timeout),
      retries: retries,
      backoff: backoff,
    );
  }

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 10),
    int retries = 2,
    Duration backoff = const Duration(milliseconds: 250),
  }) async {
    return _run(
      () => http
          .delete(url, headers: headers, body: body, encoding: encoding)
          .timeout(timeout),
      retries: retries,
      backoff: backoff,
    );
  }

  static Future<http.Response> _run(
    Future<http.Response> Function() fn, {
    required int retries,
    required Duration backoff,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await fn();
        // If token is stale (e.g. JWT_SECRET rotated), clear local session to
        // avoid loops of 403s and incorrect cached roles.
        await _maybeSignOutOnAuthError(response);
        return response;
      } catch (e) {
        lastError = e;
        final isLast = attempt == retries;
        if (isLast || !_isRetryable(e)) rethrow;
        await Future<void>.delayed(backoff * (attempt + 1));
      }
    }
    throw lastError ?? StateError('HTTP retry failed');
  }

  static bool _isRetryable(Object e) {
    if (e is TimeoutException) return true;
    if (e is http.ClientException) return true;
    return false;
  }
}
