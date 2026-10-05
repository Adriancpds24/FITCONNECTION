import 'package:rms/core/utils/url_utils.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/features/social/story_model.dart';

/// Resuelve la URL de avatar del usuario actual (misma lógica en feed, historias y visor).
class ProfileAvatar {
  static String generatedFallback(String name) {
    final label = name.trim().isEmpty ? 'Usuario' : name.trim();
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(label)}&background=random';
  }

  static String resolve(String? imagePath) {
    final normalized = (imagePath ?? '').trim();
    if (normalized.isEmpty) return '';
    return UrlUtils.resolveFullUrl(normalized);
  }

  /// URL absoluta para mostrar en avatar; fallback con iniciales si falta imagen.
  static String forPath(String? imagePath, String fallbackLabel) {
    final resolved = resolve(imagePath);
    if (resolved.isNotEmpty) return resolved;
    final label =
        fallbackLabel.trim().isEmpty ? 'Usuario' : fallbackLabel.trim();
    return generatedFallback(label);
  }

  static String forCurrentUser({Iterable<String?> extraSources = const []}) {
    final auth = AuthService();
    final social = SocialState();
    final username = (auth.username ?? social.currentUser.username).trim();

    final candidates = <String?>[
      ...extraSources,
      social.currentUser.userImage,
      for (final session in auth.sessions)
        if (session.username.trim().toLowerCase() == username.toLowerCase())
          session.userImage,
    ];

    for (final raw in candidates) {
      final url = resolve(raw);
      if (url.isNotEmpty) return url;
    }

    final label = social.currentUser.displayName.trim().isNotEmpty
        ? social.currentUser.displayName
        : (username.isNotEmpty ? username : 'Usuario');
    return generatedFallback(label);
  }

  static String forStory(StoryModel story) {
    final fromStory = resolve(story.userImage);
    if (fromStory.isNotEmpty) return fromStory;
    if (story.isOwn) return forCurrentUser();
    return generatedFallback(story.username);
  }
}
