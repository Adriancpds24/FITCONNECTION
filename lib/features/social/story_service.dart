import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/constants/api_constants.dart';
import '../auth/auth_service.dart';
import 'story_model.dart';

class StoryService {
  final AuthService _authService = AuthService();

  Map<String, String> _buildHeaders({bool includeJsonContentType = true}) {
    final token = _authService.token;
    if (token == null || token.isEmpty) {
      throw AuthException('Debes iniciar sesion para gestionar historias.');
    }

    return {
      if (includeJsonContentType)
        'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  String _detectMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/mp4';
    return 'image/jpeg';
  }

  Future<List<StoryModel>> fetchActiveStories() async {
    try {
      final url = Uri.parse('${ApiConstants.socialBaseUrl}/stories');
      final response = await http
          .get(url, headers: _buildHeaders(includeJsonContentType: false))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          errorData['error'] ?? 'No se pudieron cargar las historias.',
        );
      }

      final decoded = json.decode(response.body) as List<dynamic>;
      return decoded
          .map((item) => StoryModel.fromJson(item as Map<String, dynamic>))
          .where(
            (story) => DateTime.now().difference(story.createdAt).inHours < 24,
          )
          .toList();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al obtener historias: $e');
    }
  }

  Future<void> createStoryFromImage(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final mimeType = _detectMimeType(image.name);
      await createStoryFromBytes(
        bytes,
        fileName: image.name,
        mimeType: mimeType,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al subir historia: $e');
    }
  }

  Future<void> createStoryFromBytes(
    Uint8List bytes, {
    required String fileName,
    String? mimeType,
  }) async {
    try {
      final resolvedMimeType = mimeType ?? _detectMimeType(fileName);
      final imageData = 'data:$resolvedMimeType;base64,${base64Encode(bytes)}';

      final url = Uri.parse('${ApiConstants.socialBaseUrl}/stories');
      final response = await http
          .post(
            url,
            headers: _buildHeaders(),
            body: json.encode({'imageData': imageData}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw AuthException(
          errorData['error'] ?? 'No se pudo crear la historia.',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al subir historia: $e');
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      final url = Uri.parse('${ApiConstants.socialBaseUrl}/stories/$storyId');
      final response = await http
          .delete(url, headers: _buildHeaders(includeJsonContentType: false))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          errorData['error'] ?? 'No se pudo borrar la historia.',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al borrar historia: $e');
    }
  }

  Future<List<StoryModel>> fetchStoryArchive() async {
    try {
      final url = Uri.parse('${ApiConstants.socialBaseUrl}/stories/archive');
      final response = await http
          .get(url, headers: _buildHeaders(includeJsonContentType: false))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          errorData['error'] ?? 'No se pudo obtener el archivo de historias.',
        );
      }

      final decoded = json.decode(response.body) as List<dynamic>;
      return decoded
          .map((item) => StoryModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Error al cargar archivo de historias: $e');
    }
  }
}
