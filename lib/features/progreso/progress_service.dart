import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../auth/auth_service.dart';

class ProgressService {
  static const Duration _defaultTimeout = Duration(seconds: 25);

  Future<Map<String, String>> _headers() async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      return {'Content-Type': 'application/json'};
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>?> saveWeight(double weightKg,
      {String? date}) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.progressBaseUrl}/weight'),
            headers: await _headers(),
            body: jsonEncode(
                {'weightKg': weightKg, if (date != null) 'date': date}),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ProgressService.saveWeight error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getWeightHistory({int days = 90}) async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConstants.progressBaseUrl}/weight?days=$days'),
            headers: await _headers(),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final entries = data['entries'];
        if (entries is List) {
          return entries
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList()
              .cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      debugPrint('ProgressService.getWeightHistory error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> getReminderSettings() async {
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConstants.progressBaseUrl}/reminders'),
            headers: await _headers(),
          )
          .timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ProgressService.getReminderSettings error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> saveReminderSettings({
    bool? enabled,
    bool? mealReminders,
    bool? trainingReminders,
    bool? hydrationReminders,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) async {
    try {
      final body = <String, dynamic>{
        if (enabled != null) 'enabled': enabled,
        if (mealReminders != null) 'mealReminders': mealReminders,
        if (trainingReminders != null) 'trainingReminders': trainingReminders,
        if (hydrationReminders != null)
          'hydrationReminders': hydrationReminders,
        if (quietHoursStart != null) 'quietHoursStart': quietHoursStart,
        if (quietHoursEnd != null) 'quietHoursEnd': quietHoursEnd,
      };

      final response = await http
          .post(
            Uri.parse('${ApiConstants.progressBaseUrl}/reminders'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('ProgressService.saveReminderSettings error: $e');
    }
    return null;
  }
}
