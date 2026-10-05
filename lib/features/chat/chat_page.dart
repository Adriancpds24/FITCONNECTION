import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rms/core/utils/url_utils.dart';
import 'package:rms/core/utils/profile_avatar.dart';
import 'package:rms/features/social/post_model.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/features/social/story_model.dart';
import 'package:rms/features/social/social_service.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/features/profile/user_profile_page.dart';
import 'package:rms/features/profile/profile_view.dart';
import 'package:rms/features/home/story_view.dart';
import 'package:rms/features/chat/call_page.dart';
import 'package:rms/features/chat/chat_realtime_service.dart';
import 'package:rms/features/social/post_detail_page.dart';
import 'package:rms/features/chat/chat_persistence.dart';
import 'package:rms/features/chat/chat_platform_tools.dart'
    if (dart.library.js_interop) 'package:rms/features/chat/chat_platform_tools_web.dart';
import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';
import 'package:rms/core/theme/theme_provider.dart';

class DirectChatPage extends ConsumerStatefulWidget {
  final UserProfile user;

  const DirectChatPage({super.key, required this.user});

  @override
  ConsumerState<DirectChatPage> createState() => _DirectChatPageState();
}

class _DirectChatPageState extends ConsumerState<DirectChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final SocialService _socialService = SocialService();
  final AuthService _authService = AuthService();
  final ChatRealtimeService _realtimeService = ChatRealtimeService.instance;
  bool _isLoading = true;
  bool _isTargetOnline = false;
  bool _isTargetTyping = false;
  bool _sentTypingState = false;
  Timer? _localTypingTimer;
  Timer? _remoteTypingTimer;
  StreamSubscription<Set<String>>? _onlineUsersSubscription;
  StreamSubscription<ChatTypingEvent>? _typingSubscription;
  StreamSubscription<ChatMessageEvent>? _messageSubscription;

  String get _cacheKey {
    final currentUsername = _authService.username ?? 'guest';
    return 'chat_history_${currentUsername}_${widget.user.username}';
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;

    try {
      final max = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    } catch (_) {
      // Puede fallar si aún no hay layout completo; lo reintentamos en el next frame.
    }
  }

  @override
  void initState() {
    super.initState();
    _isTargetOnline = _realtimeService.isOnline(widget.user.username);
    _messageController.addListener(_handleTypingChanged);
    _setupRealtime();
    _loadMessages();
  }

  Future<void> _setupRealtime() async {
    await _realtimeService.connect();
    if (!mounted) return;

    _realtimeService.joinChat(widget.user.username);
    setState(() {
      _isTargetOnline = _realtimeService.isOnline(widget.user.username);
    });

    _onlineUsersSubscription = _realtimeService.onlineUsers.listen((_) {
      if (!mounted) return;
      final online = _realtimeService.isOnline(widget.user.username);
      if (online == _isTargetOnline) return;
      setState(() => _isTargetOnline = online);
    });

    _typingSubscription = _realtimeService.typingEvents.listen((event) {
      if (!mounted) return;
      if (_normalizeUsername(event.senderUsername) !=
          _normalizeUsername(widget.user.username)) {
        return;
      }

      _remoteTypingTimer?.cancel();
      setState(() => _isTargetTyping = event.isTyping);

      if (event.isTyping) {
        _remoteTypingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isTargetTyping = false);
        });
      }
    });

    _messageSubscription = _realtimeService.messageEvents.listen((event) {
      if (!mounted || !_isMessageForThisChat(event.message)) return;
      if (_normalizeUsername(
              event.message['senderUsername']?.toString() ?? '') ==
          _normalizeUsername(_authService.username ?? '')) {
        return;
      }
      if (_hasMessage(event.message['id'])) return;

      setState(() {
        _isTargetTyping = false;
        _messages.add(event.message);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
      _persistMessages();
      ChatPersistence.updateLocalConversation(
        username: widget.user.username,
        displayName: widget.user.displayName,
        imagePath: widget.user.userImage,
        lastMessage: event.message['content']?.toString(),
        bio: widget.user.bio,
        sport: widget.user.sport,
      );
    });
  }

  String _normalizeUsername(String username) => username.trim().toLowerCase();

  bool _hasMessage(dynamic id) {
    if (id == null) return false;
    final normalizedId = id.toString();
    return _messages
        .any((message) => message['id']?.toString() == normalizedId);
  }

  bool _isMessageForThisChat(Map<String, dynamic> message) {
    final myUsername = _normalizeUsername(_authService.username ?? '');
    final targetUsername = _normalizeUsername(widget.user.username);
    final sender =
        _normalizeUsername(message['senderUsername']?.toString() ?? '');
    final receiver =
        _normalizeUsername(message['receiverUsername']?.toString() ?? '');

    return (sender == targetUsername && receiver == myUsername) ||
        (sender == myUsername && receiver == targetUsername);
  }

  void _handleTypingChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;

    if (hasText && !_sentTypingState) {
      _sentTypingState = true;
      _realtimeService.sendTyping(
        targetUsername: widget.user.username,
        isTyping: true,
      );
    }

    _localTypingTimer?.cancel();
    if (hasText) {
      _localTypingTimer = Timer(
        const Duration(milliseconds: 1200),
        _sendStoppedTyping,
      );
    } else {
      _sendStoppedTyping();
    }
  }

  void _sendStoppedTyping() {
    if (!_sentTypingState) return;
    _sentTypingState = false;
    _realtimeService.sendTyping(
      targetUsername: widget.user.username,
      isTyping: false,
    );
  }

  void _showImageDialog(BuildContext context, String base64Str) {
    final theme = ref.read(themeProvider);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: theme.isDarkMode ? Colors.black87 : Colors.black87,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.loose,
          children: [
            InteractiveViewer(
              child: Image.memory(base64Decode(base64Str), fit: BoxFit.contain),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              bottom: 40,
              child: ElevatedButton.icon(
                onPressed: () {
                  try {
                    downloadBase64File(
                      base64Str,
                      'fitconnect_photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Descargando foto... 📥')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error al descargar')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.download),
                label: const Text(
                  'Descargar a mi galería',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic>? _parseSharedPostPayload(String rawContent) {
    var payloadStr = rawContent.trim();
    if (payloadStr.startsWith('"') && payloadStr.endsWith('"')) {
      try {
        payloadStr = jsonDecode(payloadStr).toString();
      } catch (_) {}
    }

    try {
      final decoded = jsonDecode(payloadStr);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    final parts = rawContent.split('|');
    if (parts.length >= 3) {
      return {
        'id': parts[0],
        'username': parts[1],
        'postImage': parts[2],
        'caption': parts.sublist(3).join('|'),
      };
    }
    return null;
  }

  Future<void> _openSharedPost(
    BuildContext context,
    Map<String, dynamic> payload,
  ) async {
    final postId = payload['id']?.toString().trim() ?? '';
    final socialState = SocialState();

    if (postId.isNotEmpty && !postId.startsWith('shared_')) {
      try {
        await socialState.syncPost(postId);
        final loaded = socialState.getPost(postId);
        if (!context.mounted) return;
        if (loaded != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostDetailPage(post: loaded),
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint('No se pudo sincronizar publicación compartida: $e');
      }
    }

    final fallback = Post.fromJson(payload);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailPage(post: fallback)),
    );
  }

  Widget _buildSharedPostMessage(
    BuildContext context,
    String contentStr,
    AppThemeState theme,
  ) {
    final payload = _parseSharedPostPayload(contentStr.substring(14));
    if (payload == null) {
      return Text(
        'Publicación compartida',
        style: TextStyle(color: theme.text, fontSize: 15),
      );
    }

    final postId = payload['id']?.toString() ?? '';
    final postUser = payload['username']?.toString() ?? '';
    var postImage = payload['postImage']?.toString() ?? '';
    final postCaption = payload['caption']?.toString() ?? '';
    var postUserImage = payload['userImage']?.toString() ?? '';

    final cached = postId.isNotEmpty ? SocialState().getPost(postId) : null;
    if (cached != null) {
      if (postUserImage.isEmpty) postUserImage = cached.userImage;
      if (postImage.isEmpty) postImage = cached.postImage;
      payload['likes'] = cached.likes;
      payload['commentsCount'] = cached.comments.length;
      payload['createdAt'] ??= cached.createdAt?.toIso8601String();
    }

    final resolvedAvatar = ProfileAvatar.forPath(postUserImage, postUser);
    final likes = (payload['likes'] as num?)?.toInt() ?? 0;
    final commentsCount = (payload['commentsCount'] as num?)?.toInt() ?? 0;
    final timeLabel = Post.formatRelativeTime(payload['createdAt']);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSharedPost(context, payload),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: SmartImage(
                      imageUrl: resolvedAvatar,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorWidget:
                          Icon(Icons.person, size: 14, color: theme.muted),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    postUser,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.text,
                    ),
                  ),
                ),
              ],
            ),
            if (postImage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SmartImage(
                    imageUrl: postImage,
                    width: double.infinity,
                    height: 150,
                    fit: BoxFit.cover,
                    errorWidget: const Icon(
                      Icons.image_not_supported,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            if (postCaption.isNotEmpty)
              Text(
                postCaption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.text),
              ),
            const SizedBox(height: 6),
            Text(
              '$likes Me gusta · $commentsCount comentarios · $timeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: theme.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseStoryDate(dynamic value, DateTime fallback) {
    return DateTime.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _openStoryFromMessage(Map<String, dynamic> storyData) {
    final image = storyData['image']?.toString() ?? '';
    if (image.trim().isEmpty) return;

    final username =
        (storyData['username']?.toString().trim().isNotEmpty ?? false)
            ? storyData['username'].toString().trim()
            : widget.user.username;
    final createdAt = _parseStoryDate(storyData['createdAt'], DateTime.now());
    final expiresAt = _parseStoryDate(
      storyData['expiresAt'],
      createdAt.add(const Duration(hours: 24)),
    );
    final myUsername = _authService.username?.trim().toLowerCase();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewPage(
          stories: [
            StoryModel(
              id: storyData['id']?.toString() ??
                  'story_message_${DateTime.now().millisecondsSinceEpoch}',
              username: username,
              userImage: storyData['userImage']?.toString(),
              image: image,
              isOwn: myUsername != null && username.toLowerCase() == myUsername,
              createdAt: createdAt,
              expiresAt: expiresAt,
              isExpired: false,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
  }

  Widget _buildStoryReplyMessage({
    required Map<String, dynamic> payload,
    required bool isMe,
    required dynamic theme,
  }) {
    final rawStory = payload['story'];
    final storyData = rawStory is Map
        ? Map<String, dynamic>.from(rawStory)
        : <String, dynamic>{};
    final image = storyData['image']?.toString() ?? '';
    final storyUsername =
        storyData['username']?.toString().trim().isNotEmpty == true
            ? storyData['username'].toString().trim()
            : widget.user.username;
    final replyText =
        (payload['text'] ?? payload['emoji'] ?? '').toString().trim();
    final textColor = isMe ? Colors.white : theme.text;
    final mutedColor =
        isMe ? Colors.white.withValues(alpha: 0.78) : theme.muted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openStoryFromMessage(storyData),
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  image.isEmpty
                      ? Container(
                          width: double.infinity,
                          height: 250,
                          color: Colors.black,
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            color: Colors.white70,
                            size: 42,
                          ),
                        )
                      : SmartImage(
                          imageUrl: UrlUtils.resolveFullUrl(image),
                          width: double.infinity,
                          height: 250,
                          fit: BoxFit.cover,
                          errorWidget: Container(
                            width: double.infinity,
                            height: 250,
                            color: Colors.black,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 42,
                            ),
                          ),
                        ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.46),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Historia',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '@$storyUsername',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: mutedColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (replyText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                replyText,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    await _loadCachedMessages();

    try {
      final messages = await _socialService.getMessages(widget.user.username);
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToBottom(animated: false);
        });
      }
      await _persistMessages();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCachedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedMessages = prefs.getString(_cacheKey);

    if (cachedMessages == null || cachedMessages.isEmpty) {
      return;
    }

    try {
      final decoded = json.decode(cachedMessages) as List<dynamic>;
      if (!mounted) {
        return;
      }

      setState(() {
        _messages
          ..clear()
          ..addAll(decoded.map((item) => Map<String, dynamic>.from(item)));
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom(animated: false);
      });
    } catch (_) {}
  }

  Future<void> _persistMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, json.encode(_messages));
  }

  Future<void> _clearLocalChatCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  Future<void> _deleteConversation(BuildContext context) async {
    final t = FitconnectLocalizations.of(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.chatDeleteConversationTitle),
        content: Text(t.chatDeleteConversationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.notificationReject),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              t.chatMoreDeleteConversation,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    try {
      await _socialService.deleteConversation(widget.user.username);
      await _clearLocalChatCache();
      await ChatPersistence.removeLocalConversation(widget.user.username);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.chatDeleteConversationDone)),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.chatDeleteConversationError)),
      );
    }
  }

  void _showChatMoreOptions(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(t.chatMoreViewProfile),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfilePage(user: widget.user),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(t.chatMoreMute),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.chatMutedSnack)),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  t.chatMoreDeleteConversation,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteConversation(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _sendStoppedTyping();
    _messageController.clear();
    setState(() {
      _messages.add({
        'content': text,
        'senderUsername': _authService.username,
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    await _persistMessages();
    await ChatPersistence.updateLocalConversation(
      username: widget.user.username,
      displayName: widget.user.displayName,
      imagePath: widget.user.userImage,
      lastMessage: text,
      bio: widget.user.bio,
      sport: widget.user.sport,
    );

    try {
      await _socialService.sendMessage(widget.user.username, text);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar el mensaje')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);
    final content = '[IMAGE]:data:image/jpeg;base64,$base64Image';

    setState(() {
      _messages.add({
        'content': content,
        'senderUsername': _authService.username,
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    await _persistMessages();
    await ChatPersistence.updateLocalConversation(
      username: widget.user.username,
      displayName: widget.user.displayName,
      imagePath: widget.user.userImage,
      lastMessage: '📷 Imagen',
      bio: widget.user.bio,
      sport: widget.user.sport,
    );

    try {
      await _socialService.sendMessage(widget.user.username, content);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al enviar la imagen')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUsername = _authService.username;
    final t = FitconnectLocalizations.of(context);
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        surfaceTintColor: theme.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.text),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: theme.border),
        ),
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfilePage(user: widget.user),
              ),
            );
          },
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.surfaceSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.border),
                ),
                child: ClipOval(
                  child: SmartImage(
                    imageUrl: widget.user.userImage,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget:
                        Icon(Icons.person, size: 22, color: theme.text),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isTargetTyping
                            ? 'Escribiendo...'
                            : (_isTargetOnline
                                ? t.chatOnlineNow
                                : 'Desconectado'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isTargetTyping || _isTargetOnline
                              ? const Color(0xFF2E7D32)
                              : theme.muted,
                          fontSize: 11,
                          fontWeight: _isTargetTyping
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(t.chatCallMockBody(widget.user.displayName)),
                ),
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CallPage(user: widget.user, isIncoming: false),
                ),
              );
            },
          ),
          IconButton(
            tooltip: FitconnectLocalizations.of(context).chatMoreTitle,
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showChatMoreOptions(context),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: theme.accent),
            )
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty && !_isTargetTyping
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClipOval(
                                child: SmartImage(
                                  imageUrl: widget.user.userImage,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  errorWidget:
                                      const Icon(Icons.person, size: 48),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.user.displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: theme.text,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                t.chatStartHistory,
                                style: TextStyle(color: theme.muted),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          controller: _scrollController,
                          reverse: false,
                          itemCount:
                              _messages.length + (_isTargetTyping ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_isTargetTyping && index == _messages.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _TypingDotsBubble(
                                    backgroundColor: theme.surfaceSoft,
                                    dotColor: theme.muted,
                                  ),
                                ),
                              );
                            }

                            final msg = _messages[index];
                            final isMe = msg['senderUsername'] == myUsername;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.75,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isMe ? theme.accent : theme.surfaceSoft,
                                    borderRadius:
                                        BorderRadius.circular(18).copyWith(
                                      bottomRight: isMe
                                          ? const Radius.circular(2)
                                          : null,
                                      bottomLeft: !isMe
                                          ? const Radius.circular(2)
                                          : null,
                                    ),
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      final contentStr =
                                          msg['content']?.toString() ?? '';

                                      if (contentStr.startsWith('[IMAGE]:')) {
                                        final b64 = contentStr
                                            .substring(8)
                                            .split(',')
                                            .last;
                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () =>
                                              _showImageDialog(context, b64),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.memory(
                                              base64Decode(b64),
                                              width: 200,
                                              height: 250,
                                              fit: BoxFit.cover,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) =>
                                                  const Icon(
                                                Icons.broken_image,
                                                size: 50,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      if (contentStr
                                          .startsWith('[STORY_REPLY]:')) {
                                        try {
                                          final payload =
                                              Map<String, dynamic>.from(
                                            jsonDecode(
                                              contentStr.substring(
                                                '[STORY_REPLY]:'.length,
                                              ),
                                            ),
                                          );
                                          return _buildStoryReplyMessage(
                                            payload: payload,
                                            isMe: isMe,
                                            theme: theme,
                                          );
                                        } catch (_) {
                                          return Text(
                                            'Historia',
                                            style: TextStyle(
                                              color: isMe
                                                  ? Colors.white
                                                  : theme.text,
                                              fontSize: 15,
                                            ),
                                          );
                                        }
                                      }

                                      if (contentStr
                                          .startsWith('[SHARED_POST]:')) {
                                        return _buildSharedPostMessage(
                                          context,
                                          contentStr,
                                          theme,
                                        );
                                      }

                                      if (contentStr
                                          .startsWith('[SHARED_PROFILE]:')) {
                                        final rawContent = contentStr.substring(
                                          '[SHARED_PROFILE]:'.length,
                                        );

                                        String username = '';
                                        String displayName = '';
                                        String userImage = '';
                                        String bio = '';
                                        String sport = '';

                                        try {
                                          var payloadStr = rawContent.trim();
                                          // Mensajes que vienen escapados: "\"{...}\"".
                                          if (payloadStr.startsWith('"') &&
                                              payloadStr.endsWith('"')) {
                                            try {
                                              payloadStr =
                                                  jsonDecode(payloadStr)
                                                      .toString();
                                            } catch (_) {}
                                          }
                                          final map = jsonDecode(payloadStr);
                                          username =
                                              map['username']?.toString() ?? '';
                                          displayName =
                                              map['displayName']?.toString() ??
                                                  '';
                                          userImage =
                                              map['userImage']?.toString() ??
                                                  '';
                                          bio = map['bio']?.toString() ?? '';
                                          sport =
                                              map['sport']?.toString() ?? '';
                                        } catch (_) {
                                          final parts = rawContent.split('|');
                                          if (parts.isNotEmpty) {
                                            username = parts[0];
                                          }
                                          if (parts.length > 1) {
                                            displayName = parts[1];
                                          }
                                          if (parts.length > 2) {
                                            userImage = parts[2];
                                          }
                                        }

                                        final fallbackName =
                                            (displayName.trim().isEmpty
                                                    ? username
                                                    : displayName)
                                                .trim();

                                        return GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (username.trim().isEmpty) {
                                              return;
                                            }

                                            final me = _authService.username;
                                            if (me != null &&
                                                me.trim().isNotEmpty &&
                                                me.trim().toLowerCase() ==
                                                    username
                                                        .trim()
                                                        .toLowerCase()) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const ProfileView(),
                                                ),
                                              );
                                              return;
                                            }

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => UserProfilePage(
                                                  user: UserProfile(
                                                    username: username,
                                                    displayName: fallbackName,
                                                    userImage: userImage,
                                                    bio: bio.isEmpty
                                                        ? '¡Hola! Estoy usando FitConnect'
                                                        : bio,
                                                    sport: sport.isEmpty
                                                        ? 'Fitness'
                                                        : sport,
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            width: 240,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: theme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: theme.border,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                ClipOval(
                                                  child: SmartImage(
                                                    imageUrl: userImage,
                                                    width: 44,
                                                    height: 44,
                                                    fit: BoxFit.cover,
                                                    errorWidget: Icon(
                                                      Icons.person,
                                                      color: theme.muted,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        fallbackName.isEmpty
                                                            ? 'Perfil'
                                                            : fallbackName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: theme.text,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        username.isEmpty
                                                            ? 'Toca para ver'
                                                            : '@$username',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: theme.muted,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.chevron_right,
                                                  color: theme.muted,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      return Text(
                                        contentStr,
                                        style: TextStyle(
                                          color:
                                              isMe ? Colors.white : theme.text,
                                          fontSize: 15,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.background,
                    boxShadow: [
                      BoxShadow(
                        color: theme.isDarkMode
                            ? Colors.black.withAlpha(60)
                            : Colors.black.withAlpha(10),
                        blurRadius: 5,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.grey,
                          ),
                          onPressed: _pickAndSendImage,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: t.chatMessageHint,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.surfaceSoft,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            style: TextStyle(color: theme.text),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _sendMessage,
                          child: Text(
                            t.chatSend,
                            style: TextStyle(
                              color: theme.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _sendStoppedTyping();
    _messageController.removeListener(_handleTypingChanged);
    _localTypingTimer?.cancel();
    _remoteTypingTimer?.cancel();
    _onlineUsersSubscription?.cancel();
    _typingSubscription?.cancel();
    _messageSubscription?.cancel();
    _realtimeService.leaveChat(widget.user.username);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _TypingDotsBubble extends StatefulWidget {
  final Color backgroundColor;
  final Color dotColor;

  const _TypingDotsBubble({
    required this.backgroundColor,
    required this.dotColor,
  });

  @override
  State<_TypingDotsBubble> createState() => _TypingDotsBubbleState();
}

class _TypingDotsBubbleState extends State<_TypingDotsBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(18).copyWith(
          bottomLeft: const Radius.circular(2),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (index) {
              final phase = (_controller.value + (index * 0.2)) % 1.0;
              final opacity = phase < 0.5 ? 0.35 + phase : 1.35 - phase;
              return Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                decoration: BoxDecoration(
                  color: widget.dotColor.withValues(
                    alpha: opacity.clamp(0.35, 1.0),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
