import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../auth/auth_service.dart';

class NutritionAnalysis {
  final String comida;
  final int proteinas;
  final int carbohidratos;
  final int grasas;
  final int calorias;

  NutritionAnalysis({
    required this.comida,
    required this.proteinas,
    required this.carbohidratos,
    required this.grasas,
    required this.calorias,
  });

  factory NutritionAnalysis.fromJson(Map<String, dynamic> json) {
    return NutritionAnalysis(
      comida: json['comida'] ?? 'Comida desconocida',
      proteinas: json['proteinas'] ?? 0,
      carbohidratos: json['carbohidratos'] ?? 0,
      grasas: json['grasas'] ?? 0,
      calorias: json['calorias'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'comida': comida,
      'proteinas': proteinas,
      'carbohidratos': carbohidratos,
      'grasas': grasas,
      'calorias': calorias,
    };
  }

  @override
  String toString() {
    return '$comida - ${calorias}kcal (P:${proteinas}g C:${carbohidratos}g G:${grasas}g)';
  }
}

class NutritionAIService {
  static const Duration _defaultTimeout = Duration(seconds: 25);

  String _guessMimeType(Uint8List bytes) {
    if (bytes.length >= 12) {
      // PNG signature
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      // JPEG SOI
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'image/jpeg';
      }
      // WEBP: "RIFF....WEBP"
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }
    return 'image/jpeg';
  }

  String _friendlyBackendError({
    required int statusCode,
    required String? backendMessage,
  }) {
    if (statusCode == 429) {
      return 'Estás haciendo muchas peticiones seguidas. Espera 10-20 segundos y prueba otra vez.';
    }
    if (statusCode >= 500) {
      return 'Ahora mismo el servidor/IA está teniendo problemas. Prueba otra vez en un momento.';
    }
    if (backendMessage != null && backendMessage.trim().isNotEmpty) {
      return backendMessage.trim();
    }
    return 'Ha ocurrido un error. Prueba otra vez.';
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _stringField(Map<String, dynamic>? json, String key) {
    if (json == null) return null;
    final v = json[key];
    return v is String ? v : null;
  }

  Future<NutritionAnalysis?> analyzeImage(Uint8List bytes) async {
    try {
      final token = AuthService().token;
      if (token == null || token.isEmpty) {
        debugPrint('NutritionAIService: missing auth token');
        return null;
      }

      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            Uri.parse('${ApiConstants.nutritionBaseUrl}/analyze-image'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'imageBase64': base64Image,
              'mimeType': 'image/jpeg',
            }),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return NutritionAnalysis.fromJson(data);
      }

      debugPrint('NutritionAIService backend error: ${response.statusCode}');
      final err = _tryParseJson(response.body);
      final backendMessage = _stringField(err, 'error');
      throw Exception(
        _friendlyBackendError(
          statusCode: response.statusCode,
          backendMessage: backendMessage,
        ),
      );
    } on TimeoutException {
      throw Exception(
          'Está tardando demasiado. Prueba otra vez (o usa una foto más clara).');
    } catch (e) {
      debugPrint('NutritionAIService error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTodayMeals() async {
    try {
      final token = AuthService().token;
      if (token == null || token.isEmpty) {
        debugPrint('NutritionAIService.getTodayMeals: missing auth token');
        return [];
      }

      final response = await http.get(
        Uri.parse('${ApiConstants.nutritionBaseUrl}/today'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final meals = data['meals'];
          if (meals is List) {
            return meals
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList()
                .cast<Map<String, dynamic>>();
          }
        } catch (e) {
          debugPrint('NutritionAIService.getTodayMeals parse error: $e');
        }
        return [];
      }

      debugPrint(
        'NutritionAIService.getTodayMeals: HTTP ${response.statusCode}',
      );
      return [];
    } on TimeoutException {
      debugPrint('NutritionAIService.getTodayMeals: timeout');
      return [];
    } catch (e) {
      debugPrint('NutritionAIService.getTodayMeals error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> saveMealFromAI({
    required String mealType,
    required NutritionAnalysis analysis,
    Uint8List? imageBytes,
  }) async {
    try {
      final token = AuthService().token;
      if (token == null || token.isEmpty) {
        debugPrint('NutritionAIService.saveMealFromAI: missing auth token');
        return null;
      }

      final imageBase64 = imageBytes == null ? null : base64Encode(imageBytes);
      final mimeType = imageBytes == null ? null : _guessMimeType(imageBytes);

      final response = await http
          .post(
            Uri.parse('${ApiConstants.nutritionBaseUrl}/meal-from-ai'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'mealType': mealType,
              if (imageBase64 != null) 'imageBase64': imageBase64,
              if (mimeType != null) 'mimeType': mimeType,
              ...analysis.toJson(),
            }),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      }

      final err = _tryParseJson(response.body);
      final backendMessage = _stringField(err, 'error');
      throw Exception(
        _friendlyBackendError(
          statusCode: response.statusCode,
          backendMessage: backendMessage,
        ),
      );
    } on TimeoutException {
      throw Exception(
          'Está tardando demasiado. Prueba otra vez en unos segundos.');
    } catch (e) {
      debugPrint('NutritionAIService.saveMealFromAI error: $e');
      rethrow;
    }
  }

  // Backwards-compatible alias used by older callers.
  Future<NutritionAnalysis?> analyzeImageWithOpenAI(Uint8List bytes) async {
    return analyzeImage(bytes);
  }

  Future<Map<String, dynamic>> getDay({
    required String dateIso,
  }) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('Necesitas iniciar sesión para ver tus comidas.');
    }

    final response = await http.get(
      Uri.parse('${ApiConstants.nutritionBaseUrl}/day?date=$dateIso'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_defaultTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final err = _tryParseJson(response.body);
    final backendMessage = _stringField(err, 'error');
    throw Exception(
      _friendlyBackendError(
        statusCode: response.statusCode,
        backendMessage: backendMessage,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getMonthlySummary({
    required int year,
    required int month,
  }) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('Necesitas iniciar sesión para ver tu historial.');
    }

    final response = await http.get(
      Uri.parse(
        '${ApiConstants.nutritionBaseUrl}/monthly-summary?year=$year&month=$month',
      ),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_defaultTimeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final days = data['days'];
      if (days is List) {
        return days
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
            .cast<Map<String, dynamic>>();
      }
      return [];
    }

    final err = _tryParseJson(response.body);
    final backendMessage = _stringField(err, 'error');
    throw Exception(
      _friendlyBackendError(
        statusCode: response.statusCode,
        backendMessage: backendMessage,
      ),
    );
  }

  Future<String> chat({
    String? message,
    List<Map<String, String>>? messages,
  }) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception(
          'Necesitas iniciar sesión para usar el chat de nutrición.');
    }

    final body = <String, dynamic>{};
    if (messages != null && messages.isNotEmpty) {
      body['messages'] = messages;
    } else {
      final text = (message ?? '').trim();
      if (text.isEmpty) {
        throw Exception('Escribe un mensaje o envía una imagen.');
      }
      body['message'] = text;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.nutritionBaseUrl}/chat'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = data['reply'];
        if (reply is String && reply.trim().isNotEmpty) return reply.trim();
        throw Exception('Respuesta inválida de la IA.');
      }

      final err = _tryParseJson(response.body);
      final backendMessage = _stringField(err, 'error');
      throw Exception(
        _friendlyBackendError(
          statusCode: response.statusCode,
          backendMessage: backendMessage,
        ),
      );
    } on TimeoutException {
      throw Exception(
          'Está tardando demasiado. Prueba otra vez en unos segundos.');
    }
  }
}
