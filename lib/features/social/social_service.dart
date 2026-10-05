import 'dart:convert';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/core/constants/api_constants.dart';
import 'package:rms/core/utils/http_retry.dart';
import 'package:rms/features/social/post_model.dart';

class SocialService {
  String get baseUrl => ApiConstants.baseUrl.replaceAll('/auth', '/social');

  Future<Map<String, String>> _getHeaders() async {
    final token = AuthService().token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Cache-Control': 'no-cache, no-store',
      'Pragma': 'no-cache',
    };
  }

  Future<Map<String, dynamic>> followUser(String targetUsername) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/follow/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) throw Exception('No se pudo seguir');
    return json.decode(response.body);
  }

  Future<void> blockUser(String targetUsername) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/block/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo bloquear al usuario');
    }
  }

  Future<void> unblockUser(String targetUsername) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/block/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo desbloquear al usuario');
    }
  }

  Future<void> unfollowUser(String targetUsername) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/unfollow/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo dejar de seguir');
    }
  }

  Future<Map<String, dynamic>> getProfile(String targetUsername) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/profile/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error al cargar perfil: ${response.statusCode}');
  }

  Future<void> updateProfile({
    String? name,
    String? bio,
    String? sport,
    String? imagePath,
    String? username,
    bool? isPrivate,
  }) async {
    final response = await HttpRetry.put(
      Uri.parse('$baseUrl/profile'),
      headers: await _getHeaders(),
      body: json.encode({
        'name': name,
        'bio': bio,
        'sport': sport,
        'imagePath': imagePath,
        'username': username,
        'isPrivate': isPrivate,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Error al actualizar el perfil');
    }
  }

  Future<bool> checkIsFollowing(String targetUsername) async {
    try {
      final data = await getProfile(targetUsername);
      return data['isFollowing'] == true;
    } catch (_) {}
    return false;
  }

  Future<List<Map<String, dynamic>>> getFollowing(String targetUsername) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/profile/user/$targetUsername/following'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getFollowers(String targetUsername) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/profile/user/$targetUsername/followers'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getFollowRequests() async {
    final url = Uri.parse('$baseUrl/follow/requests').replace(
      queryParameters: {
        '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await HttpRetry.get(
      url,
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> acceptFollowRequest(int requesterId) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/follow/request/$requesterId/accept'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('No se pudo aceptar la solicitud');
    }
  }

  Future<void> rejectFollowRequest(int requesterId) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/follow/request/$requesterId/reject'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('No se pudo rechazar la solicitud');
    }
  }

  Future<List<Map<String, dynamic>>> getUserPosts(String targetUsername) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/profile/user/$targetUsername/posts'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getMessages(String targetUsername) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/messages/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/messages/conversations'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  Future<void> sendMessage(String targetUsername, String content) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/messages/user/$targetUsername'),
      headers: await _getHeaders(),
      body: json.encode({'content': content}),
    );
    if (response.statusCode != 201) {
      throw Exception('No se pudo enviar el mensaje');
    }
  }

  Future<void> deleteConversation(String targetUsername) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/messages/user/$targetUsername'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        errorData['error'] ?? 'No se pudo eliminar la conversación',
      );
    }
  }

  Future<void> toggleLike(String postId, bool wasLiked) async {
    final response = wasLiked
        ? await HttpRetry.delete(
            Uri.parse('$baseUrl/posts/$postId/like'),
            headers: await _getHeaders(),
          )
        : await HttpRetry.post(
            Uri.parse('$baseUrl/posts/$postId/like'),
            headers: await _getHeaders(),
          );

    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo procesar el me gusta: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<Post> getPostById(String postId) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Post.fromJson(data);
    }
    throw Exception('Error al cargar la publicación: ${response.statusCode}');
  }

  Future<void> addComment(String postId, String content) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/posts/$postId/comment'),
      headers: await _getHeaders(),
      body: json.encode({'content': content}),
    );
    if (response.statusCode != 201) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo añadir el comentario: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/posts/$postId/comments'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> bookmarkPost(String postId) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/posts/$postId/bookmark'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo guardar la publicación: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<void> unbookmarkPost(String postId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/posts/$postId/bookmark'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo eliminar de guardados');
    }
  }

  Future<List<Map<String, dynamic>>> getSavedPosts() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/posts/saved'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> report(String targetId, String type, String reason) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/report'),
      headers: await _getHeaders(),
      body: json.encode({'targetId': targetId, 'type': type, 'reason': reason}),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo realizar el reporte: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<void> createStory(String image) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/stories'),
      headers: await _getHeaders(),
      body: json.encode({'imageData': image}),
    );

    if (response.statusCode != 201) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo crear la historia: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<void> deleteStory(String storyId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/stories/$storyId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo eliminar la historia: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getActiveStories() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/stories'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getStoryHistory() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/stories/history'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> createHighlight(
    String title,
    String image,
    List<String> storyImages,
  ) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/highlights'),
      headers: await _getHeaders(),
      body: json.encode({
        'title': title,
        'image': image,
        'storyImages': storyImages,
      }),
    );
    if (response.statusCode != 201) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo crear el destacado: ${errorData['error'] ?? 'Error desconocido'}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getHighlights(
    String targetUsername,
  ) async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/profile/user/$targetUsername/highlights'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> deleteHighlight(String id) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/highlights/$id'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo eliminar el destacado: ${errorData['error'] ?? 'Error desconocido'}',
      );
    }
  }

  Future<void> createPost(String content, String? image) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/posts'),
      headers: await _getHeaders(),
      body: json.encode({'content': content, 'imageData': image}),
    );
    if (response.statusCode != 201) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo crear la publicacion: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<void> deletePost(String postId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/posts/$postId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      final errorData = json.decode(response.body);
      throw Exception(
        'No se pudo eliminar la publicacion: ${errorData['details'] ?? errorData['error']}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPosts() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/posts'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final response = await HttpRetry.get(
      Uri.parse('$baseUrl/users'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    final url = Uri.parse('$baseUrl/notifications').replace(
      queryParameters: {
        '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await HttpRetry.get(
      url,
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo marcar la notificación como leída');
    }
  }

  Future<void> likeComment(String commentId) async {
    final response = await HttpRetry.post(
      Uri.parse('$baseUrl/comments/$commentId/like'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo dar like al comentario');
    }
  }

  Future<void> unlikeComment(String commentId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/comments/$commentId/like'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo quitar like al comentario');
    }
  }

  Future<void> deleteComment(String commentId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/comments/$commentId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo eliminar el comentario');
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    final response = await HttpRetry.delete(
      Uri.parse('$baseUrl/notifications/$notificationId'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo borrar la notificación');
    }
  }
}
