import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/auth_service.dart';
import '../profile/user_profile_page.dart';
import '../social/post_detail_page.dart';
import '../social/post_model.dart';
import 'package:flutter/gestures.dart';
import 'package:rms/shared/widgets/design/cards/post_card.dart';
import 'package:rms/features/chat/chat_view.dart';
import 'package:rms/features/search/search_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rms/core/theme/theme_provider.dart';

import 'package:rms/features/social/social_service.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/features/social/story_model.dart';
import 'package:rms/features/social/story_service.dart';
import 'package:rms/shared/widgets/camera_module.dart';
import 'package:rms/features/home/story_view.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';
import 'package:rms/shared/widgets/common/story_segment_ring.dart';
import '../../core/utils/profile_avatar.dart';
import '../../core/utils/url_utils.dart';
import 'package:rms/shared/widgets/common/horizontal_tab_swipe_listener.dart';

class HomePage extends ConsumerStatefulWidget {
  final ValueChanged<bool>? onCameraModeChanged;

  /// -1 = pestaña anterior, 1 = pestaña siguiente (deslizar en el feed).
  final ValueChanged<int>? onHorizontalTabSwipe;

  const HomePage({
    super.key,
    this.onCameraModeChanged,
    this.onHorizontalTabSwipe,
  });

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // Eliminamos colores estáticos para usar FeedPalette dinámico

  final SocialState _socialState = SocialState();
  final SocialService _socialService = SocialService();
  final StoryService _storyService = StoryService();
  final AuthService _authService = AuthService();
  final PageController _mainPageController = PageController(initialPage: 1);

  List<StoryModel> _activeStories = const [];
  bool _isLoadingStories = false;
  bool _isUploadingStory = false;
  int _unreadMessages = 0;
  double _horizontalDragDx = 0;
  DateTime? _horizontalDragStartedAt;

  @override
  void initState() {
    super.initState();
    _socialState.addListener(_onStateChanged);
    _loadStories();
    _syncUnreadMessages();
  }

  @override
  void dispose() {
    _socialState.removeListener(_onStateChanged);
    _mainPageController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleCameraPageChanged(int index) {
    widget.onCameraModeChanged?.call(index == 0);
  }

  void _openCameraPage() {
    if (!_mainPageController.hasClients) return;
    if (_mainPageController.page?.round() == 0) return;
    _mainPageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _handleCameraPageChanged(0);
  }

  void _closeCameraPage() {
    if (!_mainPageController.hasClients) return;
    if (_mainPageController.page?.round() == 1) return;
    _mainPageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    _handleCameraPageChanged(1);
  }

  Widget _wrapHorizontalNavigation({
    required Widget child,
    required bool isCamera,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _horizontalDragDx = 0;
        _horizontalDragStartedAt = DateTime.now();
      },
      onHorizontalDragUpdate: (details) {
        _horizontalDragDx += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        final dx = _horizontalDragDx;
        final startedAt = _horizontalDragStartedAt;
        _horizontalDragDx = 0;
        _horizontalDragStartedAt = null;

        final velocity = details.primaryVelocity ?? 0;
        if (dx.abs() < kHorizontalTabSwipeDistanceThreshold) return;
        if (startedAt != null &&
            DateTime.now().difference(startedAt) <
                kHorizontalTabSwipeMinDuration) {
          return;
        }
        if (velocity.abs() < 520) return;

        if (isCamera) {
          if (velocity < 0) _closeCameraPage();
          return;
        }

        if (velocity > 0) {
          _openCameraPage();
        } else {
          widget.onHorizontalTabSwipe?.call(1);
        }
      },
      child: child,
    );
  }

  /// Todas las historias propias (puede haber varias).
  List<StoryModel> get _ownStories {
    final list = _activeStories.where((s) => s.isOwn).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  StoryModel? get _ownActiveStory =>
      _ownStories.isEmpty ? null : _ownStories.first;

  List<StoryModel> get _otherActiveStories {
    final ownUsername = _authService.username?.trim().toLowerCase() ?? '';
    return _activeStories.where((story) {
      if (story.isOwn) return false;
      if (ownUsername.isEmpty) return true;
      return story.username.trim().toLowerCase() != ownUsername;
    }).toList(growable: false);
  }

  /// Otros usuarios agrupados por `username`, conservando el orden de primera aparición en el feed.
  List<({String username, List<StoryModel> stories})> _groupedOtherStories() {
    final order = <String>[];
    final buckets = <String, List<StoryModel>>{};
    for (final s in _otherActiveStories) {
      if (!buckets.containsKey(s.username)) {
        order.add(s.username);
        buckets[s.username] = [];
      }
      buckets[s.username]!.add(s);
    }
    for (final name in order) {
      buckets[name]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return [
      for (final name in order) (username: name, stories: buckets[name]!),
    ];
  }

  /// Orden visor estilo Instagram: bloque propio (más reciente primero), luego cada usuario en orden del feed.
  List<StoryModel> get _storiesForViewer {
    final out = <StoryModel>[];
    out.addAll(_ownStories);
    for (final g in _groupedOtherStories()) {
      out.addAll(g.stories);
    }
    return out;
  }

  String _ownStoryAvatarUrl({StoryModel? ownStory}) {
    final fromStories = <String?>[
      ownStory?.userImage,
      for (final story in _ownStories) story.userImage,
    ];
    return ProfileAvatar.forCurrentUser(extraSources: fromStories);
  }

  Future<void> _loadStories({bool showErrorSnack = true}) async {
    if (!mounted) return;
    setState(() => _isLoadingStories = true);

    try {
      if (_authService.isAuthenticated) {
        try {
          await _socialState.syncCurrentUser();
          await _authService.syncSessionFromProfile(_socialState.currentUser);
        } catch (_) {}
      }
      final stories = await _storyService.fetchActiveStories();
      if (!mounted) return;
      setState(() {
        _activeStories = stories;
      });
    } catch (error) {
      if (!mounted || !showErrorSnack) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron cargar las historias: $error'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingStories = false);
      }
    }
  }

  Future<void> _processNewStory(XFile image) async {
    if (_isUploadingStory) return;
    setState(() => _isUploadingStory = true);

    try {
      await _storyService.createStoryFromImage(image);
      await _loadStories(showErrorSnack: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Historia publicada con exito.'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo publicar la historia: $error'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingStory = false);
    }
  }

  String _detectPostMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _deleteStory(StoryModel story) async {
    try {
      await _storyService.deleteStory(story.id);
      await _loadStories(showErrorSnack: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Historia archivada correctamente.'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar la historia: $error'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  bool _isStoryViewed(StoryModel? story) {
    if (story == null) return false;
    return _socialState.isStoryViewed(story.id, isOwn: story.isOwn);
  }

  void _markStoryAsViewed(StoryModel story) {
    _socialState.markStoryAsViewed(story.id, isOwn: story.isOwn);
  }

  void _openStoriesViewer(List<StoryModel> stories, int initialIndex) {
    if (stories.isEmpty) return;
    final safeIndex = initialIndex < 0
        ? 0
        : (initialIndex >= stories.length ? stories.length - 1 : initialIndex);
    _markStoryAsViewed(stories[safeIndex]);

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (pageContext, animation, secondaryAnimation) =>
            StoryViewPage(
          stories: stories,
          initialIndex: safeIndex,
          onStoryViewed: _markStoryAsViewed,
        ),
        transitionsBuilder:
            (transitionContext, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _confirmDeleteStory(StoryModel story) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archivar historia'),
        content: Text(
          'Desaparecerá de las historias activas y quedará guardada en tu archivo. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Archivar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteStory(story);
    }
  }

  void _showOwnStoryActions(StoryModel story) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('Ver historia'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final stories = _storiesForViewer;
                  final index = stories.indexWhere(
                    (item) => item.id == story.id,
                  );
                  _openStoriesViewer(stories, index);
                },
              ),
              ListTile(
                leading: Icon(Icons.add_circle_outline),
                title: Text('Subir otra historia'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateStory();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  'Archivar historia',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _confirmDeleteStory(story);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchPage()),
    );
  }

  void _showNotifications() {
    String selectedCategory = 'Todas';
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          final allNotifications = _socialState.notifications;

          // Filtrado por categoría
          List<dynamic> filtered = allNotifications.where((n) {
            final type = n['type']?.toString().toLowerCase() ?? '';
            if (selectedCategory == 'Seguidores') {
              return type == 'follow' ||
                  type == 'follow_request' ||
                  type == 'follow_accept';
            }
            if (selectedCategory == 'Me gusta') return type == 'like';
            if (selectedCategory == 'Comentarios') return type == 'comment';
            if (selectedCategory == 'Menciones') return type == 'mention';
            if (selectedCategory == 'Desafíos') {
              return type == 'challenge' || type == 'duel';
            }
            return true;
          }).toList();

          // Filtrado por búsqueda
          if (searchQuery.isNotEmpty) {
            filtered = filtered.where((n) {
              final user = n['username']?.toString().toLowerCase() ?? '';
              final content = n['content']?.toString().toLowerCase() ?? '';
              return user.contains(searchQuery.toLowerCase()) ||
                  content.contains(searchQuery.toLowerCase());
            }).toList();
          }

          int getUnreadCount(String category) {
            return allNotifications.where((n) {
              final isUnread = n['read'] == false;
              if (!isUnread) return false;
              final type = n['type']?.toString().toLowerCase() ?? '';
              if (category == 'Seguidores') {
                return type == 'follow' ||
                    type == 'follow_request' ||
                    type == 'follow_accept';
              }
              if (category == 'Me gusta') return type == 'like';
              if (category == 'Comentarios') return type == 'comment';
              if (category == 'Menciones') return type == 'mention';
              if (category == 'Desafíos') {
                return type == 'challenge' || type == 'duel';
              }
              return true;
            }).length;
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: FeedPalette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Notificaciones',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          color: FeedPalette.text,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (allNotifications.any((n) => n['read'] == false))
                        TextButton(
                          onPressed: () async {
                            await _socialState.markAllNotificationsAsRead();
                            setStateModal(() {});
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Notificaciones leídas ocultadas',
                                ),
                              ),
                            );
                          },
                          child: Text('Marcar todo leído'),
                        ),
                    ],
                  ),
                ),
                // Barra de búsqueda
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: FeedPalette.searchField(
                    hint: 'Buscar por usuario o mensaje...',
                    onChanged: (v) => setStateModal(() => searchQuery = v),
                  ),
                ),
                const SizedBox(height: 16),
                // Categorías
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildCategoryChip(
                        'Todas',
                        Icons.notifications_none_rounded,
                        selectedCategory == 'Todas',
                        0,
                        () => setStateModal(() => selectedCategory = 'Todas'),
                      ),
                      _buildCategoryChip(
                        'Seguidores',
                        Icons.person_add_rounded,
                        selectedCategory == 'Seguidores',
                        getUnreadCount('Seguidores'),
                        () => setStateModal(
                          () => selectedCategory = 'Seguidores',
                        ),
                      ),
                      _buildCategoryChip(
                        'Me gusta',
                        Icons.favorite_rounded,
                        selectedCategory == 'Me gusta',
                        getUnreadCount('Me gusta'),
                        () =>
                            setStateModal(() => selectedCategory = 'Me gusta'),
                      ),
                      _buildCategoryChip(
                        'Comentarios',
                        Icons.comment_rounded,
                        selectedCategory == 'Comentarios',
                        getUnreadCount('Comentarios'),
                        () => setStateModal(
                          () => selectedCategory = 'Comentarios',
                        ),
                      ),
                      _buildCategoryChip(
                        'Menciones',
                        Icons.alternate_email_rounded,
                        selectedCategory == 'Menciones',
                        getUnreadCount('Menciones'),
                        () =>
                            setStateModal(() => selectedCategory = 'Menciones'),
                      ),
                      _buildCategoryChip(
                        'Desafíos',
                        Icons.emoji_events_rounded,
                        selectedCategory == 'Desafíos',
                        getUnreadCount('Desafíos'),
                        () =>
                            setStateModal(() => selectedCategory = 'Desafíos'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_off_outlined,
                                size: 60,
                                color: FeedPalette.muted.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Sin notificaciones en esta categoría',
                                style: TextStyle(
                                  color: FeedPalette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final item = filtered[idx];
                            final id = item['id']?.toString() ?? 'notif_$idx';
                            return Dismissible(
                              key: ValueKey('notif_$id'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: EdgeInsets.only(bottom: 12),
                                alignment: Alignment.centerRight,
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) async {
                                await _socialState.deleteNotification(id);
                                setStateModal(() {});
                              },
                              child: _buildNotificationCard(
                                item,
                                () => setStateModal(() {}),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChip(
    String label,
    IconData icon,
    bool isSelected,
    int count,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FilterChip(
            label: Text(label),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : FeedPalette.text,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            avatar: Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : FeedPalette.accent,
            ),
            onSelected: (_) => onTap(),
            selected: isSelected,
            showCheckmark: false,
            backgroundColor: FeedPalette.surface,
            selectedColor: FeedPalette.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? FeedPalette.accent : FeedPalette.border,
              ),
            ),
          ),
          if (count > 0 && !isSelected)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(dynamic n, VoidCallback refreshModal) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(n);
    final String type = data['type']?.toString().toLowerCase() ?? '';
    final bool isUnread = data['read'] == false;
    final t = FitconnectLocalizations.of(context);
    int? senderId;
    final rawSid = data['senderId'];
    if (rawSid is int) {
      senderId = rawSid;
    } else if (rawSid is num) {
      senderId = rawSid.toInt();
    }
    final isFollowRequest = type == 'follow_request';
    final uname = data['username']?.toString() ?? 'usuario';

    IconData typeIcon = Icons.notifications;
    Color iconColor = FeedPalette.accent;

    if (type == 'follow' ||
        type == 'follow_request' ||
        type == 'follow_accept') {
      typeIcon = Icons.person_add_rounded;
      iconColor = Colors.blue;
    } else if (type == 'like') {
      typeIcon = Icons.favorite_rounded;
      iconColor = Colors.red;
    } else if (type == 'comment') {
      typeIcon = Icons.comment_rounded;
      iconColor = Colors.green;
    } else if (type == 'mention') {
      typeIcon = Icons.alternate_email_rounded;
      iconColor = Colors.purple;
    } else if (type == 'challenge' || type == 'duel') {
      typeIcon = Icons.emoji_events_rounded;
      iconColor = Colors.orange;
    }

    final postThumbUrl = UrlUtils.resolveFullUrl(data['postImage'] ?? '');

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnread ? FeedPalette.surfaceSoft : FeedPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnread
              ? FeedPalette.accent.withValues(alpha: 0.2)
              : FeedPalette.border,
        ),
        boxShadow: [
          if (isUnread)
            BoxShadow(
              color: FeedPalette.accent.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.all(12),
            leading: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfilePage(
                      user: UserProfile(
                        username: uname,
                        displayName: uname,
                        userImage: data['image'] ?? '',
                        bio: '¡Hola! Soy parte de FitConnect.',
                        sport: 'Fitness',
                      ),
                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  ClipOval(
                    child: SmartImage(
                      imageUrl: data['image'] ?? '',
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: Icon(
                        Icons.person,
                        size: 28,
                        color: FeedPalette.muted,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: iconColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(typeIcon, size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            title: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 14, color: FeedPalette.text),
                children: [
                  TextSpan(
                    text: uname,
                    style: TextStyle(fontWeight: FontWeight.w900),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfilePage(
                              user: UserProfile(
                                username: uname,
                                displayName: uname,
                                userImage: data['image'] ?? '',
                                bio: '¡Hola! Soy parte de FitConnect.',
                                sport: 'Fitness',
                              ),
                            ),
                          ),
                        );
                      },
                  ),
                  TextSpan(text: ' ${data['content'] ?? ''}'),
                ],
              ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                data['time'] ?? '',
                style: TextStyle(color: FeedPalette.muted, fontSize: 12),
              ),
            ),
            onTap: () async {
              final id = data['id']?.toString();
              if (id != null && id.isNotEmpty) {
                await _socialState.markNotificationAsRead(id);
              }
              if (!mounted) return;
              if (isFollowRequest) return;
              if (type == 'like' || type == 'comment') {
                final postId = data['postId'];
                if (postId != null) {
                  final post = _socialState.posts.firstWhere(
                    (p) => p.id == postId.toString(),
                    orElse: () => Post(
                      id: postId.toString(),
                      username: uname,
                      userImage: data['image'] ?? '',
                      postImage: data['postImage'] ?? '',
                      caption: '',
                      likes: 0,
                      time: 'Ahora',
                    ),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailPage(post: post),
                    ),
                  );
                }
              } else if (type == 'challenge') {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SearchPage()),
                );
              } else if (type == 'follow' || type == 'follow_accept') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfilePage(
                      user: UserProfile(
                        username: uname,
                        displayName: uname,
                        userImage: data['image'] ?? '',
                        bio: '¡Hola!',
                        sport: 'Fitness',
                      ),
                    ),
                  ),
                );
              }
            },
            trailing: (type == 'like' || type == 'comment')
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SmartImage(
                      imageUrl: postThumbUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: Container(
                        width: 44,
                        height: 44,
                        color: FeedPalette.surfaceSoft,
                        child: Icon(
                          Icons.image_not_supported,
                          color: FeedPalette.muted,
                          size: 20,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          if (isFollowRequest)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await _socialState.acceptFollowRequest(
                            uname,
                            senderUserId: senderId,
                            notificationId: data['id']?.toString(),
                          );
                          refreshModal();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Solicitud de @$uname aceptada'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('No se pudo aceptar: $e')),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: FeedPalette.accent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(t.notificationAccept),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await _socialState.rejectFollowRequest(
                            uname,
                            senderUserId: senderId,
                            notificationId: data['id']?.toString(),
                          );
                          refreshModal();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Solicitud rechazada')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('No se pudo rechazar: $e')),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(t.notificationReject),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showCreatePost() {
    final pageContext = context;
    final captionController = TextEditingController();
    bool isPosting = false;
    XFile? selectedImage;
    Uint8List? selectedImageBytes;
    int charCount = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          // Make the sheet scrollable to avoid "BOTTOM OVERFLOWED" on small
          // screens and keep the main action button always reachable.
          return SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.92,
              minChildSize: 0.60,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                final media = MediaQuery.of(context);
                return Container(
                  decoration: BoxDecoration(
                    color: FeedPalette.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 12,
                      bottom:
                          media.viewInsets.bottom + media.padding.bottom + 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: FeedPalette.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Nueva publicación',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: FeedPalette.text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            final image = await picker.pickMedia();
                            if (image != null) {
                              final bytes = await image.readAsBytes();
                              setStateModal(() {
                                selectedImage = image;
                                selectedImageBytes = bytes;
                              });
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: 280,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: selectedImage == null
                                  ? LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        FeedPalette.surfaceSoft,
                                        FeedPalette.background.withValues(
                                          alpha: 0.5,
                                        ),
                                      ],
                                    )
                                  : null,
                              color:
                                  selectedImage != null ? Colors.black : null,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: FeedPalette.border.withValues(
                                  alpha: 0.5,
                                ),
                                width: 1,
                              ),
                            ),
                            child: selectedImage == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.add_a_photo_rounded,
                                          size: 40,
                                          color: FeedPalette.accent,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Comparte tu progreso',
                                        style: TextStyle(
                                          color: FeedPalette.text,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Toca para subir fotos o videos',
                                        style: TextStyle(
                                          color: FeedPalette.muted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        selectedImage!.name
                                                .toLowerCase()
                                                .endsWith('.mp4')
                                            ? Center(
                                                child: Icon(
                                                  Icons
                                                      .play_circle_fill_rounded,
                                                  size: 70,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Image.memory(
                                                selectedImageBytes!,
                                                fit: BoxFit.cover,
                                              ),
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: GestureDetector(
                                            onTap: () => setStateModal(() {
                                              selectedImage = null;
                                              selectedImageBytes = null;
                                            }),
                                            child: Container(
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.black45,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildCreativityTag(
                                Icons.auto_awesome,
                                'Plantilla AI',
                                onTap: () => setStateModal(() {
                                  final templates = [
                                    "🤖 Análisis IA: Sesión de alta intensidad completada con éxito. Rendimiento al 95%. #FitAI #SmartGym",
                                    "🧠 Optimizador FitConnect: Hoy has quemado un 15% más de calorías que tu media semanal. ¡Sigue así! #SmartFitness",
                                    "⚡ Registro Inteligente: Volumen de entrenamiento total optimizado. Nivel de esfuerzo: 8/10. #IAFitness",
                                  ];
                                  final aiTemplate =
                                      templates[math.Random().nextInt(
                                    templates.length,
                                  )];
                                  captionController.text = aiTemplate;
                                  charCount = captionController.text.length;
                                }),
                              ),
                              _buildCreativityTag(
                                Icons.trending_up_rounded,
                                'Logro',
                                onTap: () => setStateModal(() {
                                  final templates = [
                                    "📈 ¡NUEVO RECORD! He superado mi marca personal hoy. ¡Vamos por más! 🚀 #Logro #PersonalBest",
                                    "⭐ Objetivo desbloqueado: 7 días seguidos de entrenamiento. ¡La constancia es la clave! #Streak #Logro",
                                    "🎖️ ¡Aumento de nivel! Hoy me siento más fuerte que ayer. #Evolucion #FitnessGoals",
                                  ];
                                  final achievement =
                                      templates[math.Random().nextInt(
                                    templates.length,
                                  )];
                                  captionController.text = achievement;
                                  charCount = captionController.text.length;
                                }),
                              ),
                              _buildCreativityTag(
                                Icons.local_fire_department_rounded,
                                'WOD',
                                onTap: () => setStateModal(() {
                                  final templates = [
                                    "🔥 WOD del día: 21-15-9 Burpees, Thrusters y Pull-ups. ¡Tiempo récord! ⏱️ #WOD #Crossfit",
                                    "🏋️ WOD: AMRAP 20 mins de 10 Kettlebell Swings, 15 Wall Balls y 200m Sprint. #EntrenoDelDia #WOD",
                                    "🌪️ Power WOD: ¡Sufriendo pero disfrutando de la sesión de hoy! #CrossfitLife #WOD",
                                  ];
                                  final wodTemplate =
                                      templates[math.Random().nextInt(
                                    templates.length,
                                  )];
                                  captionController.text = wodTemplate;
                                  charCount = captionController.text.length;
                                }),
                              ),
                              _buildCreativityTag(
                                Icons.emoji_events_rounded,
                                '', // Icon only for trophy as in screenshot
                                onTap: () => setStateModal(() {
                                  final victory =
                                      "🏆 ¡VICTORIA! Desafío completado y medalla de oro ganada. 🥇 #Deporte #Campeon";
                                  captionController.text = victory;
                                  charCount = captionController.text.length;
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            TextField(
                              controller: captionController,
                              maxLines: 4,
                              maxLength: 250,
                              onChanged: (text) =>
                                  setStateModal(() => charCount = text.length),
                              style: TextStyle(
                                color: FeedPalette.text,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Cuéntanos cómo fue tu entrenamiento...',
                                hintStyle: TextStyle(color: FeedPalette.muted),
                                counterText: "",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: FeedPalette.background.withValues(
                                  alpha: 0.3,
                                ),
                                contentPadding: EdgeInsets.all(20),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text(
                                '$charCount/250',
                                style: TextStyle(
                                  color: charCount > 240
                                      ? Colors.red
                                      : FeedPalette.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isPosting
                                ? null
                                : () async {
                                    final trimmedCaption =
                                        captionController.text.trim();
                                    final hasImage = selectedImage != null &&
                                        selectedImageBytes != null;

                                    if (trimmedCaption.isEmpty && !hasImage) {
                                      ScaffoldMessenger.of(
                                        pageContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Añade una foto o escribe algo antes de publicar.',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }

                                    setStateModal(() => isPosting = true);

                                    try {
                                      final imageData = hasImage
                                          ? 'data:${_detectPostMimeType(selectedImage!.name)};base64,${base64Encode(selectedImageBytes!)}'
                                          : null;

                                      await _socialService.createPost(
                                        trimmedCaption,
                                        imageData,
                                      );
                                      await _socialState.syncPosts();

                                      if (pageContext.mounted) {
                                        Navigator.pop(pageContext);
                                        ScaffoldMessenger.of(
                                          pageContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '¡Publicación compartida!',
                                            ),
                                            backgroundColor: FeedPalette.accent,
                                          ),
                                        );
                                      }
                                    } catch (error) {
                                      setStateModal(() => isPosting = false);
                                      if (!mounted || !pageContext.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        pageContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'No se pudo guardar la publicacion: $error',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            style: FeedPalette.primaryButtonStyle(radius: 24),
                            child: isPosting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Compartir momento',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCreativityTag(
    IconData icon,
    String label, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(right: 8),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: FeedPalette.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: FeedPalette.border.withValues(alpha: 0.8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: FeedPalette.accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FeedPalette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateStory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Nueva historia',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionStory(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camara',
                  color: Colors.deepOrange,
                  onTap: () {
                    Navigator.pop(context);
                    _openCameraPage();
                  },
                ),
                _buildActionStory(
                  icon: Icons.video_camera_back_rounded,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final video = await picker.pickVideo(
                      source: ImageSource.camera,
                    );
                    if (video != null && mounted) {
                      await _processNewStory(video);
                    }
                  },
                ),
                _buildActionStory(
                  icon: Icons.photo_library_rounded,
                  label: 'Galeria',
                  color: Colors.blue,
                  onTap: () async {
                    Navigator.pop(context);
                    final picker = ImagePicker();
                    final image = await picker.pickMedia();
                    if (image != null && mounted) {
                      await _processNewStory(image);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionStory({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isUploadingStory ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _firstName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'de nuevo';
    return normalized.split(' ').first;
  }

  Future<void> _refreshFeed() async {
    await Future.wait([
      _loadStories(showErrorSnack: false),
      _socialState.syncPosts(),
      _socialState.syncCurrentUser(),
      _syncUnreadMessages(),
    ]);
  }

  int get _unreadNotifications {
    return _socialState.notifications.where((n) => n['read'] == false).length;
  }

  Future<void> _syncUnreadMessages() async {
    try {
      final conversations = await _socialService.getConversations();
      if (!mounted) return;
      final unreadCount = conversations.fold<int>(0, (sum, item) {
        final raw = item['unreadCount'];
        if (raw is int) return sum + raw;
        return sum + (int.tryParse(raw?.toString() ?? '') ?? 0);
      });
      setState(() => _unreadMessages = unreadCount);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadMessages = 0);
    }
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool compact = false,
    int badgeCount = 0,
  }) {
    final size = compact ? 36.0 : 42.0;
    final iconSz = compact ? 19.0 : 21.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          margin: EdgeInsets.only(left: compact ? 4 : 8),
          decoration: BoxDecoration(
            color: FeedPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: FeedPalette.border),
          ),
          child: IconButton(
            onPressed: onTap,
            tooltip: tooltip,
            icon: Icon(icon, color: FeedPalette.text, size: iconSz),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: size, height: size),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FeedPalette.accent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openMessages() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChatListView()),
    );
    if (!mounted) return;
    await _syncUnreadMessages();
  }

  Widget _buildStoryTile({
    required bool isOwn,
    required StoryModel? story,
    required StoryModel? ownStory,
    required List<StoryModel> otherStories,
    required int stackCount,
    List<StoryModel>? peerStories,
  }) {
    final peers =
        peerStories ?? (story != null ? <StoryModel>[story] : <StoryModel>[]);
    final hasOwnStory = ownStory != null;
    final isViewedStory =
        peers.isEmpty ? false : peers.every((s) => _isStoryViewed(s));
    final avatarImage = isOwn
        ? _ownStoryAvatarUrl(ownStory: ownStory)
        : (story != null
            ? ProfileAvatar.forStory(story)
            : ProfileAvatar.generatedFallback('usuario'));
    final username = isOwn ? 'Tu historia' : (story?.username ?? 'usuario');
    final tileW = MediaQuery.sizeOf(context).width < 380 ? 80.0 : 90.0;

    return GestureDetector(
      onTap: () {
        if (isOwn) {
          if (_ownStories.isEmpty) {
            _showCreateStory();
          } else {
            final flat = _storiesForViewer;
            final anchor = _ownStories.first;
            final viewerIndex = flat.indexWhere((item) => item.id == anchor.id);
            _openStoriesViewer(flat, viewerIndex < 0 ? 0 : viewerIndex);
          }
          return;
        }

        final storiesForViewer = _storiesForViewer;
        final sid = story?.id;
        if (sid == null) return;
        final viewerIndex = storiesForViewer.indexWhere(
          (item) => item.id == sid,
        );
        _openStoriesViewer(storiesForViewer, viewerIndex);
      },
      onLongPress: () {
        if (isOwn && _ownStories.isNotEmpty) {
          _showOwnStoryActions(_ownStories.first);
        } else if (isOwn) {
          _showCreateStory();
        }
      },
      child: Container(
        width: tileW,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: FeedPalette.surfaceSoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: FeedPalette.border),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                StorySegmentRing(
                  segmentCount: stackCount,
                  viewed: isViewedStory,
                  size: 62,
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child: SmartImage(
                        imageUrl: avatarImage,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: FeedPalette.surfaceSoft,
                          child: Icon(Icons.person, color: FeedPalette.muted),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isOwn && !hasOwnStory)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _showCreateStory,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Container(
                          padding: EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: FeedPalette.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              username,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                color: FeedPalette.text.withValues(alpha: 0.86),
                fontWeight: isOwn ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoriesShelf(
    StoryModel? ownStory,
    List<StoryModel> otherStories,
  ) {
    final storyGroups = _groupedOtherStories();
    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: FeedPalette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Historias activas',
                style: TextStyle(
                  color: FeedPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_ownStories.length + otherStories.length} hoy',
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoadingStories)
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: FeedPalette.accent,
                backgroundColor: FeedPalette.surfaceSoft,
              ),
            ),
          SizedBox(
            height: 114,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: 1 + storyGroups.length,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildStoryTile(
                    isOwn: true,
                    story: ownStory,
                    ownStory: ownStory,
                    otherStories: otherStories,
                    stackCount: _ownStories.isEmpty ? 0 : _ownStories.length,
                    peerStories: _ownStories.isEmpty ? null : _ownStories,
                  );
                }
                final g = storyGroups[index - 1];
                final thumb = g.stories.isNotEmpty ? g.stories.first : null;
                return _buildStoryTile(
                  isOwn: false,
                  story: thumb,
                  ownStory: ownStory,
                  otherStories: otherStories,
                  stackCount: g.stories.length,
                  peerStories: g.stories,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedHero(StoryModel? ownStory, List<StoryModel> otherStories) {
    final currentUser = _socialState.currentUser;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 12, 16, 22),
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: FeedPalette.heroGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: FeedPalette.accent.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'FitConnect',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FeedPalette.text,
                        fontSize: narrow ? 22 : 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                  _buildTopActionButton(
                    icon: Icons.add_box_outlined,
                    onTap: _showCreatePost,
                    tooltip: 'Nueva publicacion',
                    compact: narrow,
                  ),
                  _buildTopActionButton(
                    icon: Icons.favorite_border,
                    onTap: _showNotifications,
                    tooltip: 'Notificaciones',
                    compact: narrow,
                    badgeCount: _unreadNotifications,
                  ),
                  _buildTopActionButton(
                    icon: Icons.search,
                    onTap: _openSearch,
                    tooltip: 'Buscar',
                    compact: narrow,
                  ),
                  _buildTopActionButton(
                    icon: Icons.send_outlined,
                    onTap: _openMessages,
                    tooltip: 'Mensajes',
                    compact: narrow,
                    badgeCount: _unreadMessages,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Hola, ${_firstName(currentUser.displayName)}',
            style: TextStyle(
              color: FeedPalette.accent.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tu feed de hoy',
            style: TextStyle(
              color: FeedPalette.text,
              fontSize: 30,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Historias, progreso y comunidad en una vista mas clara y agradable.',
            style: TextStyle(
              color: FeedPalette.muted.withValues(alpha: 0.95),
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  currentUser.sport,
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_socialState.posts.length} publicaciones',
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildStoriesShelf(ownStory, otherStories),
        ],
      ),
    );
  }

  Widget _buildFeedSectionHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Actividad reciente',
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_socialState.posts.length}',
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Un vistazo rápido a lo que comparten tu comunidad.',
            style: TextStyle(
              color: FeedPalette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context) {
    final ownStory = _ownActiveStory;
    final otherStories = _otherActiveStories;

    return Scaffold(
      backgroundColor: FeedPalette.background,
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: FeedPalette.accent,
            backgroundColor: Colors.white,
            onRefresh: _refreshFeed,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: EdgeInsets.only(bottom: 24),
                  children: [
                    _buildFeedHero(ownStory, otherStories),
                    _buildFeedSectionHeader(),
                    AnimatedBuilder(
                      animation: _socialState,
                      builder: (context, child) {
                        if (_socialState.isLoading &&
                            _socialState.posts.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: FeedPalette.accent,
                              ),
                            ),
                          );
                        }
                        if (_socialState.posts.isEmpty) {
                          return Container(
                            margin: EdgeInsets.symmetric(horizontal: 20),
                            padding: EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: FeedPalette.surface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: FeedPalette.border),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 42,
                                  color: FeedPalette.accent,
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Aun no hay publicaciones en tu feed.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: FeedPalette.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Sigue a mas personas o comparte algo para empezar a mover esta zona.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: FeedPalette.muted,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _socialState.posts.length,
                          itemBuilder: (context, index) {
                            return PostCard(post: _socialState.posts[index]);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    return PageView(
      controller: _mainPageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: _handleCameraPageChanged,
      children: [
        _wrapHorizontalNavigation(
          isCamera: true,
          child: CameraModule(onCancel: _closeCameraPage),
        ),
        _wrapHorizontalNavigation(
          isCamera: false,
          child: _buildHomeContent(context),
        ),
      ],
    );
  }
}
