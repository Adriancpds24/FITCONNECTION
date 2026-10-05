import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../auth/auth_service.dart';
import '../../core/constants/api_constants.dart';
import 'workout_session.dart';

class TrainingService {
  Future<Map<String, String>> _getHeaders() async {
    final token = AuthService().token;
    if (token == null) return {'Content-Type': 'application/json'};
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<WorkoutSession?> getTodayWorkout() async {
    return getWorkoutForDate(DateTime.now());
  }

  Future<WorkoutSession?> getWorkoutForDate(DateTime date) async {
    try {
      final dateStr = _formatDate(date);
      final response = await http.get(
        Uri.parse('${ApiConstants.trainingBaseUrl}/day/$dateStr'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return WorkoutSession.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error en TrainingService.getWorkoutForDate: $e');
    }
    return null;
  }

  Future<bool> saveTodayProgress(
    int? workoutId,
    List<dynamic> exercises, {
    int durationSeconds = 0,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.trainingBaseUrl}/progress'),
        headers: await _getHeaders(),
        body: json.encode({
          'workoutId': workoutId,
          'exercisesList': exercises,
          'durationSeconds': durationSeconds,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error en TrainingService.saveTodayProgress: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> completeWorkout(
    int? workoutId,
    List<dynamic> exercises, {
    int durationSeconds = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.trainingBaseUrl}/complete'),
        headers: await _getHeaders(),
        body: json.encode({
          'workoutId': workoutId,
          'exercisesList': exercises,
          'durationSeconds': durationSeconds,
        }),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error en TrainingService.completeWorkout: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.trainingBaseUrl}/history'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      debugPrint('Error en TrainingService.getHistory: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getCatalogExercises() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.trainingBaseUrl}/exercises'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      debugPrint('Error en TrainingService.getCatalogExercises: $e');
    }
    return [];
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
