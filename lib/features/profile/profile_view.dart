import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rms/core/utils/media_permissions.dart';
import '../auth/auth_service.dart';

import '../social/social_service.dart';
import '../social/social_state.dart';
import '../social/user_list_page.dart';
import '../social/post_detail_page.dart';
import '../social/post_model.dart';
import '../social/story_model.dart';
import '../social/story_service.dart';
import '../home/story_view.dart';
import '../../shared/widgets/common/smart_image.dart';
import '../../shared/widgets/camera_module.dart';
import '../../shared/themes/feed_palette.dart';
import '../../core/utils/url_utils.dart';
import '../social/highlight_viewer.dart';
import '../map/reservation_service.dart';
import 'package:intl/intl.dart';
import 'edit_profile_page.dart';
import 'wearable_service.dart';
import 'package:rms/core/l10n/fitconnect_localizations.dart';

import 'account_center_pages.dart';
import '../social/follow_requests_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';
import '../chat/chat_persistence.dart';
import '../../core/l10n/locale_provider.dart';

/// Altura del grid de perfil (3 columnas, aspecto 1:1) para que no rellene todo el `TabBarView`.
double _profileTabGridHeight(
  double maxWidth, {
  required int itemCount,
  double horizontalPadding = 16,
  double verticalPadding = 6,
  double crossAxisSpacing = 2,
  double mainAxisSpacing = 2,
  int crossAxisCount = 3,
  double childAspectRatio = 1,
}) {
  if (itemCount <= 0) return verticalPadding * 2;
  final inner = (maxWidth - horizontalPadding * 2).clamp(
    0.0,
    double.infinity,
  );
  final tileWidth =
      (inner - crossAxisSpacing * (crossAxisCount - 1)) / crossAxisCount;
  final tileHeight = tileWidth / childAspectRatio;
  final rows = (itemCount + crossAxisCount - 1) ~/ crossAxisCount;
  return verticalPadding * 2 +
      rows * tileHeight +
      (rows > 1 ? (rows - 1) * mainAxisSpacing : 0);
}

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SocialState _socialState = SocialState();
  final StoryService _storyService = StoryService();
  final WearableService _wearableService = WearableService();
  final ReservationService _reservationService = ReservationService();
  List<String> _sports = [];
  List<Map<String, dynamic>> _userPosts = [];
  List<Map<String, dynamic>> _reservations = [];
  StoryModel? _ownActiveStory;
  bool _isUploadingStory = false;

  int followersCount = 0;
  int followingCount = 0;
  int postsCount = 0;

  List<Map<String, dynamic>> _cachedOwnPostsFromState() {
    final username = _socialState.currentUser.username.trim().toLowerCase();
    if (username.isEmpty) return const [];

    return _socialState.posts
        .where(
          (post) =>
              post.username.trim().toLowerCase() == username &&
              post.postImage.trim().isNotEmpty,
        )
        .map(
          (post) => <String, dynamic>{
            'id': post.id,
            'image': post.postImage,
            'content': post.caption,
            'createdAt': post.time,
            'authorUsername': post.username,
            'imagePath': post.userImage,
          },
        )
        .toList(growable: false);
  }

  void _hydrateOwnPostsFromCache() {
    final cachedPosts = _cachedOwnPostsFromState();
    if (cachedPosts.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _userPosts = cachedPosts;
      postsCount = cachedPosts.length;
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _socialState.addListener(_onStateChanged);
    _initUserSports();
    _hydrateOwnPostsFromCache();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final username = _socialState.currentUser.username;
      final postsFuture = SocialService().getUserPosts(username);
      final ownStoriesFuture = _storyService.fetchActiveStories();
      final syncUserFuture = _socialState.syncCurrentUser();
      final syncStoryHistoryFuture = _socialState.syncStoryHistory();
      await Future.wait([syncUserFuture, syncStoryHistoryFuture]);
      final posts = await postsFuture;
      StoryModel? ownStory;

      try {
        final activeStories = await ownStoriesFuture;
        for (final story in activeStories) {
          if (story.isOwn) {
            ownStory = story;
            break;
          }
        }
      } catch (e) {
        debugPrint('Error loading active story: $e');
      }

      if (mounted) {
        setState(() {
          followersCount = _socialState.currentUser.followers;
          followingCount = _socialState.currentUser.following;
          postsCount = posts.length;
          _userPosts = posts;
          _ownActiveStory = ownStory;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile data: $e');
    }

    // Sincronizar datos de salud (Wearables)
    try {
      final healthData = await _wearableService.fetchDailyData();
      await _wearableService.syncWithBackend(healthData);
      // Recargar perfil para mostrar los nuevos datos de salud sincronizados
      await _socialState.syncCurrentUser();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error syncing health data: $e');
    }

    // Cargar reservaciones (solo con sesión válida)
    if (AuthService().isAuthenticated) {
      try {
        final res = await _reservationService.getMyReservations();
        if (mounted) {
          setState(() {
            _reservations = res;
          });
        }
      } catch (e) {
        debugPrint('Error loading reservations: $e');
      }
    }
  }

  Future<void> _refreshProfile() async {
    final oldFollowers = followersCount;
    await Future.wait([
      _socialState.syncCurrentUser(),
      _socialState.syncNotifications(),
      _socialState.syncFollowing(_socialState.currentUser.username),
      _socialState.syncPosts(),
    ]);
    await _loadProfileData();
    if (!mounted) return;
    final diff = followersCount - oldFollowers;
    if (diff > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            diff == 1
                ? 'Tienes 1 nuevo seguidor'
                : 'Tienes $diff nuevos seguidores',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _initUserSports() {
    _sports = List.from(_socialState.currentUser.sports);
    if (_sports.isEmpty && _socialState.currentUser.username == 'admin') {
      _sports = ['Gimnasio', 'Running', 'Ciclismo', 'Natación'];
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _socialState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      final cachedPosts = _cachedOwnPostsFromState();
      setState(() {
        _initUserSports();
        if (cachedPosts.isNotEmpty) {
          _userPosts = cachedPosts;
          postsCount = cachedPosts.length;
        }
      });
    }
  }

  String _resolveImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return '';
    return UrlUtils.resolveFullUrl(imagePath);
  }

  void _showAddSportDialog() {
    final currentlySelected = _sports;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 20),
                  Text(
                    'Añadir Deportes',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: FeedPalette.text),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _socialState.availableSports.length,
                      itemBuilder: (context, index) {
                        final sport = _socialState.availableSports[index];
                        final isAdded = currentlySelected.contains(sport);

                        return CheckboxListTile(
                          title: Text(sport),
                          value: isAdded,
                          activeColor: FeedPalette.accent,
                          onChanged: (bool? value) async {
                            if (value == true) {
                              if (!currentlySelected.contains(sport)) {
                                currentlySelected.add(sport);
                              }
                            } else {
                              currentlySelected.remove(sport);
                            }

                            // Guardar cambios al backend
                            await _saveSports(currentlySelected);

                            if (mounted) {
                              setModalState(() {});
                              setState(() {
                                _sports = List.from(currentlySelected);
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FeedPalette.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Hecho'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveSports(List<String> sports) async {
    try {
      final sportString = sports.join(', ');
      await SocialService().updateProfile(sport: sportString);
      // Actualizar estado global
      await _socialState.syncCurrentUser();
    } catch (e) {
      debugPrint('Error saving sports: $e');
    }
  }

  void _removeSport(String sport) async {
    setState(() {
      _sports.remove(sport);
    });
    await _saveSports(_sports);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$sport eliminado de tus deportes')));
  }

  void _showEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfilePage()),
    );
  }

  Future<void> _showShareProfileToFollowingSheet(UserProfile profile) async {
    final myUsername = AuthService().username;
    if (myUsername == null || myUsername.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas iniciar sesión')),
      );
      return;
    }

    List<Map<String, dynamic>> following = [];
    try {
      following = await SocialService().getFollowing(myUsername);
    } catch (_) {
      following = [];
    }

    if (!mounted) return;

    final selected = <String>{};
    final controller = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: FeedPalette.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final q = controller.text.trim().toLowerCase();
            final filtered = q.isEmpty
                ? following
                : following.where((u) {
                    final uname =
                        (u['username'] ?? '').toString().toLowerCase();
                    final name = (u['name'] ?? u['displayName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return uname.contains(q) || name.contains(q);
                  }).toList();

            Future<void> send() async {
              if (selected.isEmpty) return;
              final payload = jsonEncode({
                'username': profile.username,
                'displayName': profile.displayName,
                'userImage': profile.userImage,
                'bio': profile.bio,
                'sport': profile.sport,
              });
              final content = '[SHARED_PROFILE]:$payload';

              final targets = selected.toList();
              Navigator.pop(sheetContext);

              try {
                for (final to in targets) {
                  await SocialService().sendMessage(to, content);

                  final row = following.firstWhere(
                    (u) => (u['username'] ?? '').toString() == to,
                    orElse: () => <String, dynamic>{},
                  );

                  await ChatPersistence.updateLocalConversation(
                    username: to,
                    displayName:
                        (row['name'] ?? row['displayName'] ?? to).toString(),
                    imagePath:
                        (row['imagePath'] ?? row['userImage'] ?? '').toString(),
                    lastMessage: '👤 Perfil compartido',
                  );
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Perfil compartido con ${targets.length} usuario(s)',
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo compartir: $e')),
                );
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: Icon(
                                  Icons.arrow_back_rounded,
                                  color: FeedPalette.text,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    'Compartir perfil',
                                    style: TextStyle(
                                      color: FeedPalette.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: controller,
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Buscar',
                              prefixIcon: Icon(
                                Icons.search,
                                color: FeedPalette.muted,
                              ),
                              filled: true,
                              fillColor: FeedPalette.surfaceSoft,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'No sigues a nadie todavía.',
                                style: TextStyle(color: FeedPalette.muted),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final u = filtered[i];
                                final uname = (u['username'] ?? '').toString();
                                final name =
                                    (u['name'] ?? u['displayName'] ?? uname)
                                        .toString();
                                final img =
                                    (u['imagePath'] ?? u['userImage'] ?? '')
                                        .toString();
                                final isOn = selected.contains(uname);

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: FeedPalette.surfaceSoft,
                                    child: ClipOval(
                                      child: SmartImage(
                                        imageUrl: img,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorWidget: Icon(
                                          Icons.person,
                                          color: FeedPalette.muted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      color: FeedPalette.text,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '@$uname',
                                    style: TextStyle(color: FeedPalette.muted),
                                  ),
                                  trailing: Checkbox(
                                    value: isOn,
                                    activeColor: FeedPalette.accent,
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v == true) {
                                          selected.add(uname);
                                        } else {
                                          selected.remove(uname);
                                        }
                                      });
                                    },
                                  ),
                                  onTap: () {
                                    setModalState(() {
                                      if (isOn) {
                                        selected.remove(uname);
                                      } else {
                                        selected.add(uname);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: selected.isEmpty ? null : send,
                          style: FeedPalette.primaryButtonStyle(radius: 14),
                          child: Text(
                            selected.isEmpty
                                ? 'Selecciona usuarios'
                                : 'Enviar a ${selected.length}',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openCameraComposer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) =>
            CameraModule(onCancel: () => Navigator.of(routeContext).pop()),
      ),
    );

    if (!mounted) return;

    try {
      await _socialState.syncPosts();
    } catch (e) {
      debugPrint('Error syncing posts after camera composer: $e');
    }

    await _loadProfileData();
  }

  Future<void> _processNewStory(XFile image) async {
    if (_isUploadingStory) return;
    setState(() => _isUploadingStory = true);

    try {
      await _storyService.createStoryFromImage(image);
      await _socialState
          .syncStoryHistory(); // Sincronizar historial inmediatamente
      await _loadProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Historia publicada con exito.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
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

  Future<void> _deleteStory(StoryModel story) async {
    try {
      await _storyService.deleteStory(story.id);
      await _loadProfileData();
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
          content: Text('No se pudo archivar la historia: $error'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _confirmDeleteStory(StoryModel story) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archivar historia'),
        content: Text(
          'Desaparecera de las historias activas y quedara guardada en tu archivo. ¿Deseas continuar?',
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

  Future<void> _openOwnStoryViewer(StoryModel story) async {
    List<StoryModel> ownStories = [story];
    try {
      final stories = await _storyService.fetchActiveStories();
      ownStories = stories.where((item) => item.isOwn).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (ownStories.isEmpty) {
        ownStories = [story];
      }
    } catch (_) {}

    final initialIndex = ownStories.indexWhere((item) => item.id == story.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewPage(
          stories: ownStories,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          onStoryViewed: (s) {
            _socialState.markStoryAsViewed(s.id, isOwn: true);
            if (mounted) setState(() {});
          },
        ),
      ),
    );

    if (!mounted) return;
    await _loadProfileData();
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
                  color: FeedPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('Ver historia'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openOwnStoryViewer(story);
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

  void _showCreateStory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: FeedPalette.border,
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
                _buildStoryAction(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camara',
                  color: FeedPalette.accent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openCameraComposer();
                  },
                ),
                _buildStoryAction(
                  icon: Icons.video_camera_back_rounded,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final cameraPermission =
                        await requestMediaPermission(ImageSource.camera);
                    if (cameraPermission != MediaPermissionStatus.granted) {
                      if (mounted) {
                        showMediaPermissionSnackBar(
                          context,
                          ImageSource.camera,
                          cameraPermission,
                        );
                      }
                      return;
                    }
                    final picker = ImagePicker();
                    final video = await picker.pickVideo(
                      source: ImageSource.camera,
                    );
                    if (video != null && mounted) {
                      await _processNewStory(video);
                    }
                  },
                ),
                _buildStoryAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Galeria',
                  color: Colors.blue,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final galleryPermission =
                        await requestMediaPermission(ImageSource.gallery);
                    if (galleryPermission != MediaPermissionStatus.granted) {
                      if (mounted) {
                        showMediaPermissionSnackBar(
                          context,
                          ImageSource.gallery,
                          galleryPermission,
                        );
                      }
                      return;
                    }
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

  Widget _buildStoryAction({
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
            padding: const EdgeInsets.all(16),
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

  @override
  Widget build(BuildContext context) {
    // Escuchar el tema para reconstruir la vista automáticamente
    ref.watch(themeProvider);
    final canGoBack = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: FeedPalette.background,
        elevation: 0,
        toolbarHeight: 50,
        title: Text(
          _socialState.currentUser.username,
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        leading: canGoBack
            ? IconButton(
                tooltip: 'Volver',
                icon: Icon(Icons.arrow_back_rounded, color: FeedPalette.text),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final theme = ref.watch(themeProvider);
              return IconButton(
                icon: Icon(
                  theme.isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: FeedPalette.text,
                ),
                onPressed: () {
                  ref.read(themeProvider.notifier).toggleDarkMode();
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              color: FeedPalette.accent,
              onRefresh: _refreshProfile,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildProfileHeader(context)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SliverAppBarDelegate(
                      TabBar(
                        controller: _tabController,
                        labelColor: FeedPalette.accent,
                        unselectedLabelColor: FeedPalette.muted,
                        indicatorColor: FeedPalette.accent,
                        onTap: (_) => setState(() {}),
                        tabs: const [
                          Tab(icon: Icon(Icons.grid_on)),
                          Tab(icon: Icon(Icons.bookmark_border)),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _tabController.index == 1
                        ? _buildSavedPosts()
                        : _buildPhotoGallery(),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 110 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    final hasOwnStory = _ownActiveStory != null;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: FeedPalette.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  final ownStory = _ownActiveStory;
                  if (ownStory != null) {
                    _openOwnStoryViewer(ownStory);
                  } else {
                    _showCreateStory();
                  }
                },
                onLongPress: () {
                  final ownStory = _ownActiveStory;
                  if (ownStory != null) {
                    _showOwnStoryActions(ownStory);
                  }
                },
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: hasOwnStory &&
                                !_socialState.isStoryViewed(
                                  _ownActiveStory!.id,
                                  isOwn: true,
                                )
                            ? LinearGradient(
                                colors: [
                                  FeedPalette.accent,
                                  FeedPalette.accent,
                                  Colors.pink,
                                ],
                              )
                            : null,
                        color: hasOwnStory
                            ? (_socialState.isStoryViewed(
                                _ownActiveStory!.id,
                                isOwn: true,
                              )
                                ? FeedPalette.border
                                : null)
                            : FeedPalette.surface,
                        border: hasOwnStory
                            ? null
                            : Border.all(color: FeedPalette.border, width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.white,
                        child: ClipOval(
                          child: SizedBox(
                            width: 74,
                            height: 74,
                            child: SmartImage(
                              imageUrl: _resolveImageUrl(
                                  _socialState.currentUser.userImage),
                              fit: BoxFit.cover,
                              errorWidget: Container(
                                color: FeedPalette.surfaceSoft,
                                child: Icon(Icons.person,
                                    color: FeedPalette.muted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!hasOwnStory)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: FeedPalette.accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.menu, color: FeedPalette.text),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => _buildSettingsMenu(context),
                          );
                        },
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatColumn(
                            label: 'Posts',
                            value: postsCount.toString(),
                          ),
                          _StatColumn(
                            label: 'Seguidores',
                            value:
                                _socialState.currentUser.followers.toString(),
                            onTap: () => _openUserList('Seguidores'),
                          ),
                          _StatColumn(
                            label: 'Siguiendo',
                            value:
                                _socialState.currentUser.following.toString(),
                            onTap: () => _openUserList('Siguiendo'),
                          ),
                        ],
                      ),
                    ),
                    if (_socialState.followRequests.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const FollowRequestsPage()),
                          ),
                          icon: Icon(Icons.person_add_rounded,
                              size: 16, color: FeedPalette.accent),
                          label: Text(
                            'Solicitudes (${_socialState.followRequests.length})',
                            style: TextStyle(
                                color: FeedPalette.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: FeedPalette.accent),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _socialState.currentUser.displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
          ),
          Text(
            '@${_socialState.currentUser.username}',
            style: TextStyle(
              fontSize: 14,
              color: FeedPalette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _socialState.currentUser.bio,
            style: TextStyle(color: FeedPalette.text, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _showEditProfile,
                  style: FeedPalette.primaryButtonStyle(),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Editar perfil',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _showShareProfileToFollowingSheet(_socialState.currentUser);
                  },
                  style: FeedPalette.softButtonStyle(),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share_outlined, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Compartir perfil',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Gamificación Card
          _buildGamificationCard(),
          const SizedBox(height: 16),
          // Wearable Dashboard
          _buildWearableDashboard(),
          const SizedBox(height: 16),
          // Próximas Reservas
          _buildReservationsSection(),
          const SizedBox(height: 16),
          // Deportes Chips
          Text(
            'Deportes:',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ..._sports.map(
                (s) => Chip(
                  label: Text(s, style: TextStyle(fontSize: 12)),
                  backgroundColor: FeedPalette.surfaceSoft,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  onDeleted: () => _removeSport(s),
                  deleteIcon: Icon(Icons.close, size: 14),
                  deleteButtonTooltipMessage: 'Eliminar',
                ),
              ),
              ActionChip(
                label: Icon(Icons.add, size: 16),
                onPressed: _showAddSportDialog,
                backgroundColor: FeedPalette.surfaceSoft,
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildHighlightsSection(),
        ],
      ),
    );
  }

  Widget _buildHighlightsSection() {
    final highlights = _socialState.getHighlightsForUser(
      _socialState.currentUser.username,
    );

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: highlights.length + 1, // +1 for the "Nueva" button
        itemBuilder: (context, index) {
          if (index == 0) {
            return GestureDetector(
              onTap: _showAddHighlightDialog,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: const CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.add, color: Colors.black, size: 30),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Nueva',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final h = highlights[index - 1];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HighlightViewer(
                  highlights: highlights,
                  initialHighlightIndex: index - 1,
                  isOwnProfile: true,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: NetworkImage(
                        _resolveImageUrl(h.coverImage),
                      ),
                      backgroundColor: Colors.grey.shade100,
                      onBackgroundImageError: (error, stackTrace) {
                        debugPrint(
                          'Error loading highlight cover: ${h.coverImage}',
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    h.title,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddHighlightDialog() {
    final titleController = TextEditingController();
    final List<String> selectedIds = [];
    final List<String> selectedImageUrls = [];
    final pastStories = _socialState.storyHistory;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Nueva historia destacada'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'Título de la historia',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Selecciona historias:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pastStories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'No hay historias pasadas.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    if (pastStories.isNotEmpty)
                      Expanded(
                        child: GridView.builder(
                          shrinkWrap: true,
                          itemCount: pastStories.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemBuilder: (context, index) {
                            final story = pastStories[index];
                            final storyId = story['id']?.toString() ?? '';
                            final storyUrl = _resolveImageUrl(
                              story['image']?.toString() ?? '',
                            );
                            final isSelected = selectedIds.contains(storyId);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    selectedIds.remove(storyId);
                                    selectedImageUrls.remove(storyUrl);
                                  } else {
                                    selectedIds.add(storyId);
                                    selectedImageUrls.add(storyUrl);
                                  }
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? FeedPalette.accent
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        storyUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          color: Colors.grey.shade200,
                                          child: Icon(
                                            Icons.broken_image,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                          child: Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () async {
                    if (titleController.text.isNotEmpty &&
                        selectedImageUrls.isNotEmpty) {
                      Navigator.pop(dialogContext);
                      try {
                        await _socialState.addHighlight(
                          titleController.text,
                          selectedImageUrls,
                        );
                      } catch (_) {}
                    } else if (selectedImageUrls.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Por favor, selecciona al menos una historia',
                          ),
                        ),
                      );
                    }
                  },
                  child: Text('Añadir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildReservationsSection() {
    if (_reservations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '📅 Próximas Reservas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _reservations.length,
            itemBuilder: (context, index) {
              final res = _reservations[index];
              if (res['status'] == 'Cancelada') return const SizedBox.shrink();

              final dateStr = res['date'] != null
                  ? DateFormat('dd MMM').format(DateTime.parse(res['date']))
                  : '---';
              final timeStr =
                  res['time']?.toString().substring(0, 5) ?? '--:--';

              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              res['centerName'] ?? 'Gimnasio',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () => _cancelReservation(res['id']),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        res['type'] ?? 'Clase',
                        style: TextStyle(
                          color: FeedPalette.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '$dateStr a las $timeStr',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _cancelReservation(int? id) async {
    if (id == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar Reserva'),
        content: Text('¿Estás seguro de que deseas cancelar esta reserva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sí, cancelar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _reservationService.cancelReservation(id);
      if (success) {
        _loadProfileData(); // Recargar datos
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reserva cancelada correctamente')),
          );
        }
      }
    }
  }

  Widget _buildWearableDashboard() {
    final user = _socialState.currentUser;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FeedPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Actividad de Hoy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              GestureDetector(
                onTap: () async {
                  bool granted = await _wearableService.requestPermissions();
                  if (granted) {
                    await _loadProfileData();
                  }
                },
                child: Text(
                  'Sincronizar',
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildModernMetric(
                icon: Icons.directions_run_rounded,
                value: user.steps.toString(),
                label: 'pasos',
                color: Colors.blue,
              ),
              _buildVerticalDivider(),
              _buildModernMetric(
                icon: Icons.local_fire_department_rounded,
                value: user.burnedCalories.toString(),
                label: 'kcal',
                color: FeedPalette.accent,
              ),
              _buildVerticalDivider(),
              _buildModernMetric(
                icon: Icons.favorite_rounded,
                value: user.heartRate.toString(),
                label: 'bpm',
                color: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: FeedPalette.muted),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(height: 30, width: 1, color: FeedPalette.border);
  }

  Widget _buildGamificationCard() {
    final user = _socialState.currentUser;
    final int nextLevelXp = user.level * 500;
    final double progress = (user.xp % 500) / 500.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FeedPalette.accent,
            FeedPalette.accent.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: FeedPalette.accent.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.stars, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Nivel ${user.level}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${user.streak} días',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'XP total',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${user.xp} / $nextLevelXp XP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildGamificationStat(
                icon: Icons.monetization_on,
                label: 'FitCoins',
                value: user.fitcoins.toString(),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 14),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGamificationStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white70, fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoGallery() {
    final images = _userPosts
        .map((post) => (post['image'] ?? '').toString())
        .where((image) => image.isNotEmpty)
        .toList(growable: false);
    final displayedImages = images;
    final itemCount = displayedImages.length + 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridHeight = _profileTabGridHeight(
          constraints.maxWidth,
          itemCount: itemCount,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: gridHeight,
            width: constraints.maxWidth,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return GestureDetector(
                    onTap: _showCreatePost,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: FeedPalette.panelDecoration(
                        radius: 20,
                        color: FeedPalette.surface,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 40, color: FeedPalette.accent),
                          const SizedBox(height: 4),
                          Text(
                            'Publicar',
                            style: TextStyle(
                              color: FeedPalette.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final imageIndex = index - 1;
                final imageUrl = displayedImages[imageIndex];
                Post? post;
                try {
                  post = _socialState.posts.firstWhere(
                    (p) =>
                        p.postImage == imageUrl &&
                        p.username == _socialState.currentUser.username,
                  );
                } catch (_) {
                  post = Post(
                    id: 'my_post_$imageIndex',
                    username: _socialState.currentUser.username,
                    userImage: _socialState.currentUser.userImage,
                    postImage: imageUrl,
                    likes: 0,
                    caption: '',
                    time: 'Ahora',
                    comments: [],
                  );
                }

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostDetailPage(post: post!),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: FeedPalette.panelDecoration(
                      radius: 20,
                      color: FeedPalette.surface,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SmartImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: FeedPalette.surfaceSoft,
                          child: Icon(
                            Icons.broken_image,
                            color: FeedPalette.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSavedPosts() {
    final savedPosts = _socialState.posts.where((p) => p.isBookmarked).toList();

    if (savedPosts.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border, size: 56, color: FeedPalette.muted),
              const SizedBox(height: 12),
              Text(
                'Aún no has guardado nada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: FeedPalette.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Guarda fotos y videos para verlos más tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(color: FeedPalette.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = savedPosts.length;
        final gridHeight = _profileTabGridHeight(
          constraints.maxWidth,
          itemCount: itemCount,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: gridHeight,
            width: constraints.maxWidth,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1,
              ),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                final post = savedPosts[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostDetailPage(post: post),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: FeedPalette.panelDecoration(
                      radius: 20,
                      color: FeedPalette.surface,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SmartImage(
                        imageUrl: post.postImage,
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: FeedPalette.surfaceSoft,
                          child: Icon(Icons.broken_image,
                              color: FeedPalette.muted),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
          const SizedBox(height: 20),
          ListTile(
            leading: Icon(Icons.settings, color: FeedPalette.text),
            title: Text('Configuración y privacidad',
                style: TextStyle(color: FeedPalette.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.bookmark_border, color: FeedPalette.text),
            title: Text('Guardado', style: TextStyle(color: FeedPalette.text)),
            onTap: () {
              Navigator.pop(context);
              _tabController.animateTo(1);
            },
          ),
          ListTile(
            leading: Icon(Icons.history, color: FeedPalette.text),
            title:
                Text('Tu actividad', style: TextStyle(color: FeedPalette.text)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityPage()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.exit_to_app, color: Colors.red),
            title: Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
              ref.read(usernameProvider.notifier).state = null;
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              }
            },
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          return SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.55,
              maxChildSize: 0.92,
              builder: (ctx, scrollController) {
                final media = MediaQuery.of(ctx);
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 20,
                      bottom:
                          media.viewInsets.bottom + media.padding.bottom + 20,
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
                        const SizedBox(height: 20),
                        Text(
                          'Nueva publicación',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: FeedPalette.text),
                        ),
                        const SizedBox(height: 20),
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
                          child: Container(
                            height: 200,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: FeedPalette.border, width: 2),
                            ),
                            child: selectedImage == null
                                ? const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate,
                                        size: 50,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'Subir contenido desde galería',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: selectedImage!.name
                                            .toLowerCase()
                                            .endsWith('.mp4')
                                        ? Center(
                                            child: Icon(
                                              Icons.videocam,
                                              size: 50,
                                              color: FeedPalette.accent,
                                            ),
                                          )
                                        : Image.memory(
                                            selectedImageBytes!,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: captionController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText:
                                'Escribe un pie de foto o cuenta tu progreso...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                                      ScaffoldMessenger.of(pageContext)
                                          .showSnackBar(
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

                                      await SocialService().createPost(
                                        trimmedCaption,
                                        imageData,
                                      );
                                      await _socialState.syncPosts();
                                      await _loadProfileData();

                                      if (!mounted || !pageContext.mounted) {
                                        return;
                                      }
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(pageContext)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Publicación creada con éxito.',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (error) {
                                      setStateModal(() => isPosting = false);
                                      if (!mounted || !pageContext.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(pageContext)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'No se pudo guardar la publicación: $error',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FeedPalette.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
                                    'Publicar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
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

  String _detectPostMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    return 'image/jpeg';
  }

  void _openUserList(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserListPage(
          title: title,
          username: _socialState.currentUser.username,
          fetchUsers: (u) => title == 'Seguidores'
              ? SocialService().getFollowers(u)
              : SocialService().getFollowing(u),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatColumn({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: FeedPalette.text,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: FeedPalette.muted),
          ),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: FeedPalette.background, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

// Nueva página de Configuración
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final SocialState _socialState = SocialState();

  void _showAccountsModal() {
    final List<AuthSession> sessions = AuthService().sessions;
    final currentUsername = AuthService().username;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: FeedPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Cambiar cuenta',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: FeedPalette.text),
              ),
              const SizedBox(height: 10),
              ...sessions.map((session) {
                final isCurrent = session.username == currentUsername;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(session.userImage),
                  ),
                  title: Text(
                    session.username,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!isCurrent) {
                      try {
                        await AuthService().switchAccount(session.username);
                        // Actualizar providers reactivos (prefs por sí solos no "emiten" cambios)
                        ref.read(usernameProvider.notifier).state =
                            session.username;
                        ref.read(themeProvider.notifier).refreshForUser();
                        if (!mounted) return;
                        setState(() {});
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al cambiar: $e')),
                          );
                        }
                      }
                    }
                  },
                );
              }),
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: Colors.blue),
                title: Text(
                  'Añadir cuenta',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAddAccountDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(themeProvider);
    final appLocale = ref.watch(appLocaleProvider);

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Configuración y Apariencia',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        backgroundColor: FeedPalette.surface,
        elevation: 0,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar',
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey.shade200,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _buildSection('Tu cuenta'),
          ListTile(
            leading: Icon(Icons.account_box_outlined),
            title: Text('Centro de cuentas'),
            subtitle: Text('Contraseñas, seguridad, datos personales...'),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsCenterPage()),
              );
            },
          ),
          _buildSection('Cómo usas FitConnect'),
          ListTile(
            leading: Icon(Icons.bookmark_border, color: FeedPalette.text),
            title: Text('Guardado', style: TextStyle(color: FeedPalette.text)),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedPostsPage()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.history, color: FeedPalette.text),
            title: Text('Archivo'),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoryArchivePage()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.timer_outlined),
            title: Text('Tiempo en la app'),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppUsagePage()),
              );
            },
          ),
          _buildSection('Privacidad'),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "DEBUG: Selector de tema abajo",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
          _buildThemeSelector(ref, currentTheme),
          const Divider(),
          _buildSection('Idioma'),
          ListTile(
            leading: Icon(Icons.language, color: FeedPalette.text),
            title: Text('Idioma', style: TextStyle(color: FeedPalette.text)),
            subtitle: Text(
              appLocale == null
                  ? 'Sistema'
                  : (appLocale.languageCode.startsWith('es')
                      ? 'Español'
                      : 'English'),
              style: TextStyle(color: FeedPalette.muted),
            ),
            trailing: Icon(Icons.chevron_right, color: FeedPalette.muted),
            onTap: () async {
              final selected = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                backgroundColor: FeedPalette.surface,
                builder: (ctx) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading:
                              Icon(Icons.settings, color: FeedPalette.text),
                          title: Text('Sistema',
                              style: TextStyle(color: FeedPalette.text)),
                          trailing: appLocale == null
                              ? Icon(Icons.check, color: FeedPalette.accent)
                              : null,
                          onTap: () => Navigator.pop(ctx, 'system'),
                        ),
                        ListTile(
                          leading: Icon(Icons.flag, color: FeedPalette.text),
                          title: Text('Español',
                              style: TextStyle(color: FeedPalette.text)),
                          trailing:
                              appLocale?.languageCode.startsWith('es') == true
                                  ? Icon(Icons.check, color: FeedPalette.accent)
                                  : null,
                          onTap: () => Navigator.pop(ctx, 'es'),
                        ),
                        ListTile(
                          leading: Icon(Icons.flag_outlined,
                              color: FeedPalette.text),
                          title: Text('English',
                              style: TextStyle(color: FeedPalette.text)),
                          trailing: (appLocale != null &&
                                  appLocale.languageCode.startsWith('en'))
                              ? Icon(Icons.check, color: FeedPalette.accent)
                              : null,
                          onTap: () => Navigator.pop(ctx, 'en'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              );
              if (selected == null) return;
              if (selected == 'system') {
                ref.read(appLocaleProvider.notifier).useSystem();
              } else {
                ref
                    .read(appLocaleProvider.notifier)
                    .setLocale(Locale(selected));
              }
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.lock_outline),
            title: Text('Cuenta privada'),
            subtitle: Text(
              'Solo personas que apruebes podrán ver tus fotos y videos.',
            ),
            value: _socialState.currentUser.isPrivate,
            onChanged: (val) async {
              try {
                await _socialState.updateProfile(isPrivate: val);
                if (mounted) setState(() {});
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al cambiar privacidad: $e')),
                  );
                }
              }
            },
          ),
          _buildSection('Inicios de sesión'),
          ListTile(
            leading: Icon(Icons.add, color: Colors.blue),
            title: Text(
              'Añadir o cambiar de cuenta',
              style: TextStyle(color: Colors.blue),
            ),
            onTap: () {
              _showAccountsModal();
            },
          ),
          ListTile(
            leading: Icon(Icons.logout, color: Colors.red),
            title: Text(
              'Cerrar sesión en ${_socialState.currentUser.username}',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Cerrar sesión'),
                  content: Text('¿Estás seguro de que quieres salir?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await AuthService().signOut();
                ref.read(usernameProvider.notifier).state = null;
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                }
              }
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(WidgetRef ref, AppThemeState currentTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('Personalización'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Color de la aplicación',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: FeedPalette.text,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _ThemeButton(
                    color: const Color(0xFFFF6A2B),
                    isSelected: currentTheme.type == AppThemeType.orange,
                    onTap: () => ref
                        .read(themeProvider.notifier)
                        .setTheme(AppThemeType.orange),
                  ),
                  const SizedBox(width: 16),
                  _ThemeButton(
                    color: const Color(0xFF22C55E),
                    isSelected: currentTheme.type == AppThemeType.green,
                    onTap: () => ref
                        .read(themeProvider.notifier)
                        .setTheme(AppThemeType.green),
                  ),
                  const SizedBox(width: 16),
                  _ThemeButton(
                    color: const Color(0xFF0EA5E9),
                    isSelected: currentTheme.type == AppThemeType.blue,
                    onTap: () => ref
                        .read(themeProvider.notifier)
                        .setTheme(AppThemeType.blue),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.grey,
        ),
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
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
              const SizedBox(height: 24),
              Text(
                'Añadir cuenta',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  child: Icon(Icons.person, color: Colors.grey),
                ),
                title: Text(
                  'Iniciar sesión en una cuenta existente',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  child: Icon(Icons.person_add, color: Colors.grey),
                ),
                title: Text(
                  'Crear nueva cuenta',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/register',
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

enum _ArchiveViewMode { grid, calendar }

enum _ArchiveHighlightActionType { createNew, addToExisting }

class _ArchiveHighlightActionResult {
  final _ArchiveHighlightActionType type;
  final String? highlightId;

  const _ArchiveHighlightActionResult.createNew()
      : type = _ArchiveHighlightActionType.createNew,
        highlightId = null;

  const _ArchiveHighlightActionResult.addToExisting(this.highlightId)
      : type = _ArchiveHighlightActionType.addToExisting;
}

class StoryArchivePage extends StatefulWidget {
  const StoryArchivePage({super.key});

  @override
  State<StoryArchivePage> createState() => _StoryArchivePageState();
}

class _StoryArchivePageState extends State<StoryArchivePage> {
  final StoryService _storyService = StoryService();
  final SocialState _socialState = SocialState();
  List<StoryModel> _archiveStories = [];
  bool _isLoading = true;
  String? _error;
  _ArchiveViewMode _viewMode = _ArchiveViewMode.grid;
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  String _resolveImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return '';
    return UrlUtils.resolveFullUrl(imagePath);
  }

  Future<void> _loadArchive() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stories = await _storyService.fetchStoryArchive();
      if (!mounted) return;
      setState(() {
        _archiveStories = stories;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmPermanentDelete(StoryModel story) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar permanentemente'),
        content: Text(
          'Esta historia se borrará para siempre y no podrá recuperarse ni usarse en destacados. ¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Eliminar',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storyService.deleteStory(story.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Historia eliminada permanentemente')),
          );
          _loadArchive();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
        }
      }
    }
  }

  Future<void> _showAddOneToHighlightDialog(StoryModel story) async {
    final highlights = _socialState.getHighlightsForUser(
      _socialState.currentUser.username,
    );
    final imageUrl = _resolveImageUrl(story.image);

    final action = await showModalBottomSheet<_ArchiveHighlightActionResult>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Añadir a destacados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: FeedPalette.accent),
                ),
                title: Text(
                  'Nuevo destacado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  const _ArchiveHighlightActionResult.createNew(),
                ),
              ),
              if (highlights.isNotEmpty) ...[
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tus destacados',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                ...highlights.map(
                  (h) => ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(h.coverImage),
                    ),
                    title: Text(h.title),
                    onTap: () => Navigator.pop(
                      sheetContext,
                      _ArchiveHighlightActionResult.addToExisting(h.id),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action.type == _ArchiveHighlightActionType.createNew) {
      await _showCreateNewFromArchive(imageUrl);
      return;
    }

    final highlightId = action.highlightId;
    if (highlightId == null || highlightId.isEmpty) return;

    try {
      await _socialState.addStoryToHighlight(highlightId, imageUrl);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Agregado a destacados')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar a destacados: $e')),
        );
      }
    }
  }

  Future<void> _showCreateNewFromArchive(String imageUrl) async {
    final titleController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nuevo destacado'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(hintText: 'Título'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty) {
                Navigator.pop(context);
                await _socialState.addHighlight(titleController.text, [
                  imageUrl,
                ]);
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Destacado creado')),
                  );
                }
              }
            },
            child: Text('Crear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Archivo de historias',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: RefreshIndicator(
        onRefresh: _loadArchive,
        child: Builder(
          builder: (context) {
            if (_isLoading && _archiveStories.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_error != null && _archiveStories.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 140),
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'No se pudo cargar el archivo.\n$_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    child: ElevatedButton(
                      onPressed: _loadArchive,
                      child: Text('Reintentar'),
                    ),
                  ),
                ],
              );
            }

            if (_archiveStories.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 150),
                  Icon(Icons.history_toggle_off, size: 72, color: Colors.grey),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Aun no tienes historias archivadas',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                // Memories Section (Un día como hoy)
                _buildMemoriesSection(),

                // Top Tab Bar Mockup
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setState(() => _viewMode = _ArchiveViewMode.grid),
                        child: _buildArchiveTabIcon(
                          Icons.grid_on_outlined,
                          _viewMode == _ArchiveViewMode.grid,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(
                          () => _viewMode = _ArchiveViewMode.calendar,
                        ),
                        child: _buildArchiveTabIcon(
                          Icons.calendar_month_outlined,
                          _viewMode == _ArchiveViewMode.calendar,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _viewMode == _ArchiveViewMode.grid
                      ? _buildGridView()
                      : _buildCalendarView(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 0.6,
      ),
      itemCount: _archiveStories.length,
      itemBuilder: (context, index) {
        final story = _archiveStories[index];
        final imageUrl = _resolveImageUrl(story.image);

        return _ArchiveStoryGridItem(
          imageUrl: imageUrl,
          dayDigit: story.createdAt.day.toString(),
          onTap: () => _openArchiveStoryViewer(index),
          onHighlightTap: () => _showAddOneToHighlightDialog(story),
          onDeleteTap: () => _confirmPermanentDelete(story),
        );
      },
    );
  }

  Widget _buildCalendarView() {
    // Implementación simplificada de calendario tipo IG
    final daysInMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    ).day;
    final firstDayOfWeek = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      1,
    ).weekday; // 1=Lun, 7=Dom

    // Offset para que lunes sea el primer día
    final offset = (firstDayOfWeek - 1);

    return Column(
      children: [
        // Month Selector
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _focusedMonth = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month - 1,
                  ),
                ),
              ),
              Text(
                '${_getMonthName(_focusedMonth.month)} ${_focusedMonth.year}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: FeedPalette.text),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _focusedMonth = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month + 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Week Days Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              Text('lun.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('mar.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('mié.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('jue.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('vie.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('sáb.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text('dom.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 8,
            ),
            itemCount: daysInMonth + offset,
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();

              final day = index - offset + 1;
              final date = DateTime(
                _focusedMonth.year,
                _focusedMonth.month,
                day,
              );

              // Buscar historias para este día
              final dayStories = _archiveStories
                  .where(
                    (s) =>
                        s.createdAt.year == date.year &&
                        s.createdAt.month == date.month &&
                        s.createdAt.day == date.day,
                  )
                  .toList();

              if (dayStories.isEmpty) {
                return Center(
                  child: Text('$day', style: TextStyle(color: Colors.black54)),
                );
              }

              // Si hay historias, mostrar burbuja con miniatura
              final firstStory = dayStories.first;
              return GestureDetector(
                onTap: () => _openArchiveStoryViewer(
                  _archiveStories.indexOf(firstStory),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: FeedPalette.border,
                            width: 0.5,
                          ),
                          image: DecorationImage(
                            image: NetworkImage(
                              _resolveImageUrl(firstStory.image),
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return months[month - 1];
  }

  Widget _buildArchiveTabIcon(IconData icon, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isActive ? Colors.black : Colors.grey.shade400,
          size: 24,
        ),
        if (isActive)
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  Widget _buildMemoriesSection() {
    // Buscar historias de "Hoy hace EXACTAMENTE 1 o más años"
    final now = DateTime.now();
    final memories = _archiveStories.where((s) {
      final years = now.year - s.createdAt.year;
      return s.createdAt.day == now.day &&
          s.createdAt.month == now.month &&
          years >= 1;
    }).toList();

    if (memories.isEmpty) return const SizedBox.shrink();

    final memory = memories.first;
    final years = now.year - memory.createdAt.year;
    final label = "Hoy hace $years ${years == 1 ? 'año' : 'años'}";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recuerdos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _resolveImageUrl(memory.image),
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Un día como hoy',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(label, style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _openArchiveStoryViewer(
                        _archiveStories.indexOf(memory),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('Compartir'),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: Icon(Icons.close, size: 20, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openArchiveStoryViewer(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            StoryViewPage(stories: _archiveStories, initialIndex: initialIndex),
      ),
    );
  }
}

class _ArchiveStoryGridItem extends StatelessWidget {
  final String imageUrl;
  final String dayDigit;
  final VoidCallback onTap;
  final VoidCallback onHighlightTap;
  final VoidCallback onDeleteTap;

  const _ArchiveStoryGridItem({
    required this.imageUrl,
    required this.dayDigit,
    required this.onTap,
    required this.onHighlightTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        // Opción rápida para borrar o destacar
        showModalBottomSheet(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.star_border, color: FeedPalette.accent),
                  title: Text('Añadir a destacados'),
                  onTap: () {
                    Navigator.pop(context);
                    onHighlightTap();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Eliminar del archivo'),
                  onTap: () {
                    Navigator.pop(context);
                    onDeleteTap();
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: Icon(Icons.broken_image),
            ),
          ),
          // Day indicator (optional, like IG grid)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                dayDigit,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Tu actividad',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: FeedPalette.text,
            fontSize: 20,
          ),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Un lugar donde administrar tu actividad.',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: FeedPalette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Aquí puedes ver y administrar lo que has hecho en FitConnect.',
                    style: TextStyle(color: FeedPalette.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildModernItem(
                  context,
                  Icons.favorite_border,
                  'Interacciones',
                  'Me gusta, comentarios y respuestas',
                  Colors.pink,
                ),
                _buildModernItem(
                  context,
                  Icons.access_time,
                  'Tiempo en la app',
                  'Consulta cuánto tiempo pasas en FitConnect',
                  FeedPalette.accent,
                ),
                _buildModernItem(
                  context,
                  Icons.history,
                  'Historial de búsqueda',
                  'Consulta tus búsquedas recientes',
                  Colors.blue,
                ),
                _buildModernItem(
                  context,
                  Icons.link,
                  'Enlaces visitados',
                  'Consulta los enlaces que has abierto',
                  Colors.green,
                ),
                _buildModernItem(
                  context,
                  Icons.download_for_offline_outlined,
                  'Descargar información',
                  'Copia de lo que has compartido',
                  Colors.purple,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: FeedPalette.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: FeedPalette.muted, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, size: 18, color: FeedPalette.muted),
        onTap: () {
          if (title == 'Tiempo en la app') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppUsagePage()),
            );
          } else if (title == 'Interacciones') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _ActivityInteractionsPage(),
              ),
            );
          } else if (title == 'Historial de búsqueda') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _SearchHistoryPage()),
            );
          } else if (title == 'Enlaces visitados') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _VisitedLinksPage()),
            );
          } else if (title == 'Descargar información') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _DownloadInfoPage()),
            );
          }
        },
      ),
    );
  }
}

class _ActivityInteractionsPage extends StatelessWidget {
  const _ActivityInteractionsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Interacciones',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: FeedPalette.text),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: ListView(
        children: [
          _buildItem(Icons.favorite, 'Me gusta', '82 publicaciones'),
          _buildItem(Icons.comment, 'Comentarios', '14 comentarios'),
          _buildItem(Icons.reply, 'Respuestas', '2 respuestas'),
        ],
      ),
    );
  }

  Widget _buildItem(IconData icon, String title, String count) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(count, style: TextStyle(color: Colors.grey)),
          Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () {},
    );
  }
}

class _SearchHistoryPage extends StatelessWidget {
  const _SearchHistoryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Historial de búsqueda',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: FeedPalette.text),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
        actions: [
          TextButton(
            onPressed: () {},
            child: Text('Borrar todo', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildSearchItem('mario_fitness'),
          _buildSearchItem('suplementos proteinas'),
          _buildSearchItem('rutina crossfit'),
          _buildSearchItem('ana_runner'),
        ],
      ),
    );
  }

  Widget _buildSearchItem(String term) {
    return ListTile(
      leading: Icon(Icons.history, color: Colors.grey),
      title: Text(term),
      trailing: Icon(Icons.close, size: 18),
      onTap: () {},
    );
  }
}

class _VisitedLinksPage extends StatelessWidget {
  const _VisitedLinksPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Enlaces visitados',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: FeedPalette.text),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No has visitado ningun enlace recientemente.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadInfoPage extends StatelessWidget {
  const _DownloadInfoPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Descargar información',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: FeedPalette.text),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Obtén una copia de tu actividad en FitConnect.',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: FeedPalette.text),
            ),
            const SizedBox(height: 12),
            Text(
              'Te enviaremos un correo electronico con un enlace a un archivo con tus fotos, comentarios, informacion del perfil y mucho mas.',
              style: TextStyle(color: FeedPalette.muted, height: 1.5),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Solicitar descarga'),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Tardaremos hasta 30 dias en generar el archivo.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});

  @override
  State<SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> {
  final SocialService _service = SocialService();
  List<Map<String, dynamic>> _savedPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final posts = await _service.getSavedPosts();
      if (mounted) {
        setState(() {
          _savedPosts = posts;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text('Tus guardados',
            style: TextStyle(
                color: FeedPalette.text, fontWeight: FontWeight.bold)),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedPosts.isEmpty
              ? const Center(child: Text('No tienes publicaciones guardadas'))
              : GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: _savedPosts.length,
                  itemBuilder: (context, index) {
                    final post = _savedPosts[index];
                    return InkWell(
                      onTap: () {
                        // Navegar al detalle si es necesario
                      },
                      child: SmartImage(imageUrl: post['image'] ?? ''),
                    );
                  },
                ),
    );
  }
}

class AppUsagePage extends StatelessWidget {
  const AppUsagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = SocialState().appUsageDuration;
    final hours = usage.inHours;
    final minutes = usage.inMinutes % 60;

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Tiempo en la app',
          style:
              TextStyle(color: FeedPalette.text, fontWeight: FontWeight.bold),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, FeedPalette.accent.withValues(alpha: 0.05)],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: FeedPalette.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    size: 64,
                    color: FeedPalette.accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Estadísticas de sesión',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${hours}h ${minutes}m',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '¡Estás teniendo una sesión productiva!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 48),
                _buildStatRow('Límite diario', 'No establecido'),
                const SizedBox(height: 16),
                _buildStatRow('Promedio semanal', '45m / día'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Recordatorios de límite',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Text(
            value,
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class AccountsCenterPage extends StatelessWidget {
  const AccountsCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          t.accountCenterTitle,
          style:
              TextStyle(color: FeedPalette.text, fontWeight: FontWeight.bold),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.accountCenterSubtitle,
            style: TextStyle(color: FeedPalette.muted),
          ),
          const SizedBox(height: 24),
          _buildItem(
            context,
            Icons.person_outline,
            t.profilesLabel,
            SocialState().currentUser.username,
            onTap: () {
              Navigator.pop(context); // Salir del centro de cuentas
              _showLocalAccountsModal(context); // Mostrar modal de perfiles
            },
          ),
          _buildItem(
            context,
            Icons.security,
            t.passwordAndSecurity,
            null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SecurityPage()),
              );
            },
          ),
          _buildItem(
            context,
            Icons.description_outlined,
            t.personalDetailsTitle,
            null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PersonalDetailsPage()),
              );
            },
          ),
          _buildItem(
            context,
            Icons.payment,
            t.paymentsTitle,
            null,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentsPage()),
              );
            },
          ),
          const SizedBox(height: 40),
          Text(
            t.accountSettingsHeader,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: FeedPalette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.accountSettingsFooter,
            style: TextStyle(color: FeedPalette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showLocalAccountsModal(BuildContext context) {
    final List<AuthSession> sessions = AuthService().sessions;
    final currentUsername = AuthService().username;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: FeedPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Cambiar cuenta',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: FeedPalette.text),
              ),
              const SizedBox(height: 10),
              ...sessions.map((session) {
                final isCurrent = session.username == currentUsername;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(session.userImage),
                  ),
                  title: Text(
                    session.username,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (!isCurrent) {
                      try {
                        await AuthService().switchAccount(session.username);
                        // Aquí no tenemos acceso a `ref` (no es Consumer*). La actualización
                        // reactiva del tema/usuario se hace desde `SettingsPage`.
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al cambiar: $e')),
                          );
                        }
                      }
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    String? subtitle, {
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: FeedPalette.text),
      title: Text(title, style: TextStyle(color: FeedPalette.text)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: FeedPalette.muted))
          : null,
      trailing: Icon(Icons.chevron_right, color: FeedPalette.muted),
      onTap: onTap,
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? FeedPalette.text : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isSelected ? Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}
