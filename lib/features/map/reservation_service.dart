import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../auth/auth_service.dart';
import '../../core/constants/api_constants.dart';

class ReservationService {
  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getHeaders() async {
    final token = _authService.token;
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<Map<String, dynamic>>> getMyReservations() async {
    try {
      final token = _authService.token;
      if (token == null || token.trim().isEmpty) {
        return [];
      }
      final response = await http.get(
        Uri.parse('${ApiConstants.apiHost}/reservations/me'),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        // Sesión caducada o token inválido: evitar ruido en consola.
        return [];
      }
      debugPrint(
        'Reservations request failed: ${response.statusCode} ${response.body}',
      );
      return [];
    } catch (e) {
      debugPrint('Error fetching reservations: $e');
      return [];
    }
  }

  Future<bool> createReservation({
    required int sportsCenterId,
    required String date,
    required String time,
    required String type,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.apiHost}/reservations'),
        headers: await _getHeaders(),
        body: json.encode({
          'sportsCenterId': sportsCenterId,
          'date': date,
          'time': time,
          'type': type,
        }),
      );

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('Error creating reservation: $e');
      return false;
    }
  }

  Future<bool> cancelReservation(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.apiHost}/reservations/$id'),
        headers: await _getHeaders(),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error canceling reservation: $e');
      return false;
    }
  }
}
