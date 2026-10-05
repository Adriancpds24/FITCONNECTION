import 'dart:async';

import 'package:flutter/material.dart';

import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/features/social/post_model.dart';
import 'package:rms/features/social/social_service.dart';
import 'package:rms/features/chat/chat_page.dart';
import 'package:rms/features/chat/chat_realtime_service.dart';
import 'package:rms/shared/themes/feed_palette.dart';

import 'package:rms/features/chat/chat_persistence.dart';
import 'package:rms/core/utils/profile_avatar.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';

class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final SocialService _socialService = SocialService();
  final AuthService _authService = AuthService();
  final ChatRealtimeService _realtimeService = ChatRealtimeService.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allUsers = [];
  Set<String> _onlineUsernames = <String>{};
  StreamSubscription<Set<String>>? _onlineUsersSubscription;

  @override
  void initState() {
    super.initState();
    _setupRealtimePresence();
    _loadScreenData();
  }

  @override
  void dispose() {
    _onlineUsersSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setupRealtimePresence() async {
    await _realtimeService.connect();
    if (!mounted) return;
    setState(() => _onlineUsernames = _realtimeService.currentOnlineUsernames);
    _onlineUsersSubscription = _realtimeService.onlineUsers.listen((users) {
      if (!mounted) return;
      setState(() => _onlineUsernames = users);
    });
  }

  Future<void> _loadScreenData({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _socialService.getConversations(),
        _socialService.getAllUsers(),
        ChatPersistence.readLocalConversations(),
      ]);

      final remoteConversations = List<Map<String, dynamic>>.from(
        results[0] as List,
      );
      final allUsers = List<Map<String, dynamic>>.from(results[1] as List);
      final localConversations = List<Map<String, dynamic>>.from(
        results[2] as List,
      );

      if (!mounted) return;

      final currentUsername = (_authService.username ?? '').toLowerCase();
      final filteredUsers = allUsers.where((user) {
        return (user['username']?.toString().toLowerCase() ?? '') !=
            currentUsername;
      }).toList(growable: false);

      final mergedConversations = _mergeConversations(
        remoteConversations,
        localConversations,
      );

      setState(() {
        _allUsers = filteredUsers;
        _conversations = mergedConversations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los mensajes: $error')),
      );
    }
  }

  List<Map<String, dynamic>> _mergeConversations(
    List<Map<String, dynamic>> remoteConversations,
    List<Map<String, dynamic>> localConversations,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    // Primero las remotas (servidor)
    for (final conversation in remoteConversations) {
      final username = conversation['username']?.toString() ?? '';
      if (username.isEmpty) continue;

      merged[_normalizeKey(username)] = {
        'username': username,
        'displayName':
            conversation['name']?.toString().trim().isNotEmpty == true
                ? conversation['name'].toString()
                : username,
        'imagePath': conversation['imagePath']?.toString() ?? '',
        'bio': conversation['bio']?.toString() ?? '',
        'sport': conversation['sport']?.toString() ?? 'Fitness',
        'lastMessage': conversation['content']?.toString() ?? '',
        'createdAt': conversation['createdAt']?.toString(),
        'unreadCount': conversation['unreadCount'] ?? 0,
        'isDraft': false,
      };
    }

    // Luego las locales (borradores/historial persistente)
    for (final local in localConversations) {
      final username = local['username']?.toString() ?? '';
      if (username.isEmpty) continue;

      final key = _normalizeKey(username);
      if (merged.containsKey(key)) {
        // Si ya existe de la remota, actualizamos el mensaje si el local es más reciente?
        // Por ahora, priorizamos la remota pero nos aseguramos de que los datos locales no se pierdan
        continue;
      }

      merged[key] = {
        'username': username,
        'displayName': local['name']?.toString().trim().isNotEmpty == true
            ? local['name'].toString()
            : username,
        'imagePath': local['imagePath']?.toString() ?? '',
        'bio': local['bio']?.toString() ?? '',
        'sport': local['sport']?.toString() ?? 'Fitness',
        'lastMessage': local['lastMessage'] ?? 'Empieza una conversación',
        'createdAt': local['updatedAt'] ?? local['addedAt'],
        'unreadCount': 0,
        'isDraft': true,
      };
    }

    final mergedList = merged.values.toList(growable: false);
    mergedList.sort((left, right) {
      final rightDate = _parseDate(right['createdAt']);
      final leftDate = _parseDate(left['createdAt']);
      return rightDate.compareTo(leftDate);
    });
    return mergedList;
  }

  String _normalizeKey(String value) => value.trim().toLowerCase();

  bool _isOnline(String username) {
    return _onlineUsernames.contains(_normalizeKey(username));
  }

  DateTime _parseDate(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatConversationTime(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';

    const weekDays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];

    if (diff.inDays < 7) {
      return weekDays[date.weekday - 1];
    }

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  UserProfile _buildUserProfile(Map<String, dynamic> data) {
    final username = data['username']?.toString() ?? 'usuario';
    final displayName =
        data['displayName']?.toString().trim().isNotEmpty == true
            ? data['displayName'].toString()
            : (data['name']?.toString().trim().isNotEmpty == true
                ? data['name'].toString()
                : username);

    final imagePath =
        data['imagePath']?.toString() ?? data['userImage']?.toString();
    return UserProfile(
      username: username,
      displayName: displayName,
      userImage: ProfileAvatar.forPath(imagePath, displayName),
      bio: data['bio']?.toString() ?? 'Sin biografía disponible.',
      sport: data['sport']?.toString() ?? 'Fitness',
    );
  }

  List<Map<String, dynamic>> get _filteredConversations {
    if (_searchQuery.trim().isEmpty) {
      return _conversations;
    }

    final normalized = _searchQuery.trim().toLowerCase();
    return _conversations.where((conversation) {
      final username = conversation['username']?.toString().toLowerCase() ?? '';
      final displayName =
          conversation['displayName']?.toString().toLowerCase() ?? '';
      final lastMessage =
          conversation['lastMessage']?.toString().toLowerCase() ?? '';
      return username.contains(normalized) ||
          displayName.contains(normalized) ||
          lastMessage.contains(normalized);
    }).toList(growable: false);
  }

  Future<void> _openConversation(Map<String, dynamic> userData) async {
    final profile = _buildUserProfile(userData);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DirectChatPage(user: profile)),
    );

    if (!mounted) return;
    await _loadScreenData(showLoading: false);
  }

  Future<void> _startConversation(Map<String, dynamic> userData) async {
    await ChatPersistence.updateLocalConversation(
      username: userData['username']?.toString() ?? '',
      displayName: userData['name']?.toString(),
      imagePath: userData['imagePath']?.toString(),
      bio: userData['bio']?.toString(),
      sport: userData['sport']?.toString(),
    );
    if (!mounted) return;
    await _loadScreenData(showLoading: false);
    if (!mounted) return;
    await _openConversation(userData);
  }

  void _showNewConversationSheet() {
    if (_allUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay usuarios disponibles para chatear'),
        ),
      );
      return;
    }

    final pageContext = context;
    final searchController = TextEditingController();
    String localQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
          final filteredUsers = _allUsers.where((user) {
            if (localQuery.trim().isEmpty) return true;
            final normalized = localQuery.trim().toLowerCase();
            final username = user['username']?.toString().toLowerCase() ?? '';
            final name = user['name']?.toString().toLowerCase() ?? '';
            return username.contains(normalized) || name.contains(normalized);
          }).toList(growable: false);

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FeedPalette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nueva conversación',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: FeedPalette.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: (value) =>
                        setModalState(() => localQuery = value),
                    style: FeedPalette.bodyTextStyle,
                    decoration: FeedPalette.textFieldDecoration(
                      hint: 'Busca una persona...',
                      prefixIcon: Icon(Icons.search, color: FeedPalette.muted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron usuarios.',
                              style: TextStyle(color: FeedPalette.muted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final profile = _buildUserProfile(user);

                              return ListTile(
                                leading: _ChatAvatar(
                                  imageUrl: profile.userImage,
                                  label: profile.displayName,
                                  isOnline: _isOnline(profile.username),
                                ),
                                title: Text(
                                  profile.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: FeedPalette.text,
                                  ),
                                ),
                                subtitle: Text(
                                  '@${profile.username}',
                                  style: TextStyle(color: FeedPalette.muted),
                                ),
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _startConversation(user);
                                  if (!pageContext.mounted) return;
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(searchController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _filteredConversations;

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
        toolbarHeight: 84,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mensajes activos',
              style: TextStyle(
                color: FeedPalette.text,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                letterSpacing: -0.9,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Conversaciones y avisos en una sola bandeja.',
              style: TextStyle(
                color: FeedPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_square, color: FeedPalette.accent),
            onPressed: _showNewConversationSheet,
            tooltip: 'Nueva conversación',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Container(
                decoration: FeedPalette.panelDecoration(
                  radius: 22,
                  color: FeedPalette.surface,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: FeedPalette.bodyTextStyle,
                  decoration: FeedPalette.textFieldDecoration(
                    hint: 'Busca personas o conversaciones',
                    prefixIcon: Icon(Icons.search, color: FeedPalette.muted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, color: FeedPalette.muted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    radius: 22,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ).copyWith(
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: FeedPalette.accent,
                onRefresh: () => _loadScreenData(showLoading: false),
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: FeedPalette.accent,
                        ),
                      )
                    : filteredConversations.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 90, 20, 24),
                            children: [
                              const SizedBox(height: 140),
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: FeedPalette.muted.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  _searchQuery.isEmpty
                                      ? 'Aún no tienes conversaciones'
                                      : 'No se encontraron chats',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: FeedPalette.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                            itemCount: filteredConversations.length,
                            itemBuilder: (context, index) {
                              final conversation = filteredConversations[index];
                              final unreadCount =
                                  conversation['unreadCount'] as int? ?? 0;
                              final hasUnread = unreadCount > 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: DecoratedBox(
                                  decoration: FeedPalette.panelDecoration(
                                    radius: 24,
                                    color: FeedPalette.highlightSurface(
                                      emphasized: hasUnread,
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    leading: _ChatAvatar(
                                      imageUrl: conversation['imagePath']
                                              ?.toString() ??
                                          '',
                                      label: conversation['displayName']
                                              ?.toString() ??
                                          conversation['username']
                                              ?.toString() ??
                                          'U',
                                      isOnline: _isOnline(
                                        conversation['username']?.toString() ??
                                            '',
                                      ),
                                    ),
                                    title: Text(
                                      conversation['username']?.toString() ??
                                          'usuario',
                                      style: TextStyle(
                                        color: FeedPalette.onHighlightSurface,
                                        fontWeight: hasUnread
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      conversation['lastMessage']
                                                  ?.toString()
                                                  .startsWith('[IMAGE]:') ==
                                              true
                                          ? '📷 Imagen'
                                          : conversation['lastMessage']
                                                      ?.toString()
                                                      .startsWith(
                                                        '[STORY_REPLY]:',
                                                      ) ==
                                                  true
                                              ? 'Historia'
                                              : conversation['lastMessage']
                                                          ?.toString()
                                                          .startsWith(
                                                              '[SHARED_POST]:') ==
                                                      true
                                                  ? '📢 Publicación compartida'
                                                  : conversation['lastMessage']
                                                              ?.toString()
                                                              .isNotEmpty ==
                                                          true
                                                      ? conversation[
                                                              'lastMessage']
                                                          .toString()
                                                      : 'Empieza una conversación',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: hasUnread
                                            ? FeedPalette.onHighlightSurface
                                                .withValues(alpha: 0.82)
                                            : FeedPalette.muted,
                                        fontWeight: hasUnread
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatConversationTime(
                                            conversation['createdAt'],
                                          ),
                                          style: TextStyle(
                                            color: hasUnread
                                                ? FeedPalette.accent
                                                : FeedPalette.muted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (hasUnread)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 6),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: FeedPalette.accent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                999,
                                              ),
                                            ),
                                            child: Text(
                                              unreadCount.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () =>
                                        _openConversation(conversation),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String imageUrl;
  final String label;
  final bool isOnline;

  const _ChatAvatar({
    required this.imageUrl,
    required this.label,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = ProfileAvatar.forPath(imageUrl, label);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: FeedPalette.surfaceSoft,
          child: ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: SmartImage(
                imageUrl: resolvedUrl,
                fit: BoxFit.cover,
                errorWidget: Icon(Icons.person, color: FeedPalette.muted),
              ),
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: FeedPalette.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
