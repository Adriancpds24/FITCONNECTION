import 'package:health/health.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../auth/auth_service.dart';
import '../../core/constants/api_constants.dart';

class WearableService {
  final Health health = Health();

  Future<Map<String, String>> _getHeaders() async {
    final token = AuthService().token;
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;

    final types = [
      HealthDataType.STEPS,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.HEART_RATE,
    ];

    bool? hasPermissions = await health.hasPermissions(types);
    if (hasPermissions != true) {
      return await health.requestAuthorization(types);
    }
    return true;
  }

  Future<Map<String, dynamic>> fetchDailyData() async {
    // Si estamos en la web o en un emulador no compatible, devolveremos datos mock
    if (kIsWeb ||
        (kDebugMode &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return _getMockData();
    }

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      int steps = 0;
      int calories = 0;
      int heartRate = 0;

      // Obtener pasos
      try {
        steps = await health.getTotalStepsInInterval(midnight, now) ?? 0;
      } catch (e) {
        debugPrint('Error fetching steps: $e');
      }

      // Obtener calorías y ritmo cardiaco (requiere fetch general)
      final types = [
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.HEART_RATE,
      ];
      List<HealthDataPoint> healthData = await health.getHealthDataFromTypes(
        startTime: midnight,
        endTime: now,
        types: types,
      );

      for (var point in healthData) {
        final valString = point.value.toString();
        final doubleValue = double.tryParse(valString) ?? 0.0;

        if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          calories += doubleValue.toInt();
        } else if (point.type == HealthDataType.HEART_RATE) {
          heartRate = doubleValue.toInt();
        }
      }

      return {
        'steps': steps,
        'burnedCalories': calories,
        'heartRate': heartRate,
      };
    } catch (e) {
      debugPrint('Error in WearableService.fetchDailyData: $e');
      return _getMockData();
    }
  }

  Map<String, dynamic> _getMockData() {
    return {'steps': 8420, 'burnedCalories': 450, 'heartRate': 72};
  }

  Future<bool> syncWithBackend(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiHost}/wearable/sync'),
        headers: await _getHeaders(),
        body: json.encode(data),
      );

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error syncing wearable data: $e');
      return false;
    }
  }
}
