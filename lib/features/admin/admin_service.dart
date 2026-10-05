import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../auth/auth_service.dart';

class AdminService {
  final AuthService _authService = AuthService();

  Map<String, String> get _headers {
    final token = _authService.token?.trim();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse(
      '${ApiConstants.adminBaseUrl}$path',
    ).replace(queryParameters: queryParameters);
  }

  Future<dynamic> _decode(http.Response response) async {
    if (response.body.isEmpty) {
      return null;
    }

    return json.decode(response.body);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _uri(path, queryParameters);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: _headers);
        break;
      case 'POST':
        response = await http.post(
          uri,
          headers: _headers,
          body: json.encode(body ?? const {}),
        );
        break;
      case 'PUT':
        response = await http.put(
          uri,
          headers: _headers,
          body: json.encode(body ?? const {}),
        );
        break;
      case 'PATCH':
        response = await http.patch(
          uri,
          headers: _headers,
          body: json.encode(body ?? const {}),
        );
        break;
      case 'DELETE':
        response = await http.delete(
          uri,
          headers: _headers,
          body: body == null ? null : json.encode(body),
        );
        break;
      default:
        throw Exception('Metodo HTTP no soportado: $method');
    }

    final decoded = await _decode(response);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (decoded is Map<String, dynamic> && decoded['error'] != null) {
      throw Exception(decoded['error']);
    }

    throw Exception('La API admin ha devuelto ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getOverview() async {
    final response = await _request('GET', '/overview');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> getUsers({String search = ''}) async {
    final response = await _request(
      'GET',
      '/users',
      queryParameters: search.trim().isEmpty ? null : {'search': search.trim()},
    );
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> updateUserRole(int userId, String role) async {
    await _request('PATCH', '/users/$userId/role', body: {'role': role});
  }

  Future<void> updateUserStatus(int userId, bool isActive) async {
    await _request(
      'PATCH',
      '/users/$userId/status',
      body: {'isActive': isActive},
    );
  }

  Future<void> deleteUser({int? userId, String? username}) async {
    if (userId == null && (username == null || username.trim().isEmpty)) {
      throw Exception('Debes indicar un usuario para eliminar');
    }

    await _request(
      'DELETE',
      '/users',
      body: {
        if (userId != null) 'id': userId,
        if (username != null && username.trim().isNotEmpty)
          'username': username.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> sendPasswordReset(int userId) async {
    final response = await _request('POST', '/users/$userId/password-reset');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<Map<String, dynamic>>> getReports({String status = ''}) async {
    final response = await _request(
      'GET',
      '/reports',
      queryParameters: status.trim().isEmpty ? null : {'status': status.trim()},
    );
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> updateReport(
    int reportId, {
    required String status,
    String? resolutionNotes,
  }) async {
    await _request(
      'PATCH',
      '/reports/$reportId',
      body: {'status': status, 'resolutionNotes': resolutionNotes},
    );
  }

  Future<List<Map<String, dynamic>>> getModerationPosts() async {
    final response = await _request('GET', '/moderation/posts');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getModerationComments() async {
    final response = await _request('GET', '/moderation/comments');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getModerationStories() async {
    final response = await _request('GET', '/moderation/stories');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> deletePost(int postId) async {
    await _request('DELETE', '/moderation/posts/$postId');
  }

  Future<void> deleteComment(int commentId) async {
    await _request('DELETE', '/moderation/comments/$commentId');
  }

  Future<void> archiveStory(int storyId) async {
    await _request('DELETE', '/moderation/stories/$storyId');
  }

  Future<List<Map<String, dynamic>>> getExercises() async {
    final response = await _request('GET', '/catalog/exercises');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createExercise(
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'POST',
      '/catalog/exercises',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateExercise(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'PUT',
      '/catalog/exercises/$id',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deleteExercise(int id) async {
    await _request('DELETE', '/catalog/exercises/$id');
  }

  Future<List<Map<String, dynamic>>> getFoods() async {
    final response = await _request('GET', '/catalog/foods');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createFood(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/catalog/foods', body: payload);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateFood(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _request('PUT', '/catalog/foods/$id', body: payload);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deleteFood(int id) async {
    await _request('DELETE', '/catalog/foods/$id');
  }

  Future<List<Map<String, dynamic>>> getSports() async {
    final response = await _request('GET', '/catalog/sports');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createSport(Map<String, dynamic> payload) async {
    final response = await _request('POST', '/catalog/sports', body: payload);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateSport(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'PUT',
      '/catalog/sports/$id',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deleteSport(int id) async {
    await _request('DELETE', '/catalog/sports/$id');
  }

  Future<List<Map<String, dynamic>>> getWorkoutTemplates() async {
    final response = await _request('GET', '/catalog/workout-templates');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createWorkoutTemplate(
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'POST',
      '/catalog/workout-templates',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateWorkoutTemplate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'PUT',
      '/catalog/workout-templates/$id',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deleteWorkoutTemplate(int id) async {
    await _request('DELETE', '/catalog/workout-templates/$id');
  }

  Future<List<Map<String, dynamic>>> getNutritionTemplates() async {
    final response = await _request('GET', '/catalog/nutrition-templates');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createNutritionTemplate(
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'POST',
      '/catalog/nutrition-templates',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> updateNutritionTemplate(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _request(
      'PUT',
      '/catalog/nutrition-templates/$id',
      body: payload,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deleteNutritionTemplate(int id) async {
    await _request('DELETE', '/catalog/nutrition-templates/$id');
  }

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final response = await _request('GET', '/audit-logs');
    return (response as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
}

class AdminDashboardData {
  final Map<String, dynamic> overview;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> stories;
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> foods;
  final List<Map<String, dynamic>> sports;
  final List<Map<String, dynamic>> workoutTemplates;
  final List<Map<String, dynamic>> nutritionTemplates;
  final List<Map<String, dynamic>> auditLogs;
  final Map<String, String> sectionErrors;
  final DateTime loadedAt;

  const AdminDashboardData({
    required this.overview,
    required this.users,
    required this.reports,
    required this.posts,
    required this.comments,
    required this.stories,
    required this.exercises,
    required this.foods,
    required this.sports,
    required this.workoutTemplates,
    required this.nutritionTemplates,
    required this.auditLogs,
    this.sectionErrors = const {},
    required this.loadedAt,
  });
}
