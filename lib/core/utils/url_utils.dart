import 'package:flutter/foundation.dart';

import '../../core/constants/api_constants.dart';

class UrlUtils {
  static String _rewriteLocalhostForMobile(String url) {
    if (kIsWeb) return url;

    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme) return url;

    final host = parsed.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1' && host != '0.0.0.0') {
      return url;
    }

    final apiUri = Uri.parse(ApiConstants.apiHost);
    return parsed
        .replace(
          scheme: apiUri.scheme,
          host: apiUri.host,
          port: apiUri.hasPort ? apiUri.port : null,
        )
        .toString();
  }

  static String resolveFullUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('data:')) return raw;

    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final parsed = Uri.tryParse(raw);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        return _rewriteLocalhostForMobile(raw);
      }
      return '';
    }

    // Handle malformed duplicated scheme like "https://host/https://..."
    final embeddedHttp = raw.indexOf('http://');
    final embeddedHttps = raw.indexOf('https://');
    final embedded = embeddedHttp >= 0
        ? embeddedHttp
        : (embeddedHttps >= 0 ? embeddedHttps : -1);
    if (embedded > 0) {
      final candidate = raw.substring(embedded).trim();
      final parsed = Uri.tryParse(candidate);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        return _rewriteLocalhostForMobile(candidate);
      }
    }

    final baseUrl = ApiConstants.apiHost.replaceAll('/api', '');

    if (url.startsWith('/uploads') || url.startsWith('/')) {
      return _rewriteLocalhostForMobile('$baseUrl$url');
    }

    if (url.startsWith('uploads/')) {
      return _rewriteLocalhostForMobile('$baseUrl/$url');
    }

    return _rewriteLocalhostForMobile('$baseUrl/uploads/$url');
  }
}
