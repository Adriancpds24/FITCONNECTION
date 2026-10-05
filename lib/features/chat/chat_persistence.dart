import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rms/features/auth/auth_service.dart';

class ChatPersistence {
  static String get _draftChatsKey =>
      'chat_drafts_${AuthService().username ?? 'guest'}';

  static Future<List<Map<String, dynamic>>> readLocalConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftChatsKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> updateLocalConversation({
    required String username,
    String? displayName,
    String? imagePath,
    String? lastMessage,
    String? bio,
    String? sport,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final conversations = await readLocalConversations();

    final index = conversations.indexWhere(
      (c) => c['username'].toString().toLowerCase() == username.toLowerCase(),
    );

    final now = DateTime.now().toIso8601String();

    if (index != -1) {
      final existing = conversations.removeAt(index);
      conversations.insert(0, {
        ...existing,
        if (displayName != null) 'name': displayName,
        if (imagePath != null) 'imagePath': imagePath,
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (bio != null) 'bio': bio,
        if (sport != null) 'sport': sport,
        'updatedAt': now,
      });
    } else {
      conversations.insert(0, {
        'username': username,
        'name': displayName ?? username,
        'imagePath': imagePath ?? '',
        'lastMessage': lastMessage ?? 'Empieza una conversación',
        'bio': bio ?? '',
        'sport': sport ?? 'Fitness',
        'updatedAt': now,
        'addedAt': now,
      });
    }

    await prefs.setString(_draftChatsKey, json.encode(conversations));
  }

  static Future<void> removeLocalConversation(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final conversations = await readLocalConversations();
    final normalized = username.trim().toLowerCase();

    conversations.removeWhere(
      (conversation) =>
          conversation['username']?.toString().toLowerCase() == normalized,
    );

    await prefs.setString(_draftChatsKey, json.encode(conversations));
  }
}
