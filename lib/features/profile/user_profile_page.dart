import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rms/features/social/post_model.dart';
import 'package:rms/features/chat/chat_page.dart';
import 'package:rms/features/social/social_service.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/features/social/user_list_page.dart';
import 'package:rms/features/social/highlight_viewer.dart';
import 'package:rms/features/social/post_detail_page.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';
import 'package:rms/shared/widgets/common/story_segment_ring.dart';
import 'package:rms/features/social/story_model.dart';
import 'package:rms/features/home/story_view.dart';
import 'package:rms/features/admin/admin_service.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/features/chat/chat_persistence.dart';

class UserProfilePage extends StatefulWidget {
  final UserProfile user;

  const UserProfilePage({super.key, required this.user});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  bool isFollowing = false;
  bool isRequested = false;
  bool _isPrivate = false;
  bool _restricted = false;
  bool isLoading = true;
  int followersCount = 0;
  int followingCount = 0;
  int postsCount = 0;
  List<Map<String, dynamic>> _userPosts = [];
  final SocialService _socialService = SocialService();
  final AdminService _adminService = AdminService();
  late TabController _tabController;
  late String _displayName;
  late String _bio;
  late String _sport;
  late String _userImage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isPrivate = widget.user.isPrivate;
    _displayName = widget.user.displayName;
    _bio = widget.user.bio;
    _sport = widget.user.sport;
    _userImage = widget.user.userImage;
    _checkFollowingStatus();
    SocialState().addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    SocialState().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {
        isFollowing = SocialState().isFollowing(widget.user.username);
        isRequested = SocialState().isFollowRequested(widget.user.username);
        if (widget.user.username == SocialState().currentUser.username) {
          postsCount = SocialState().posts.length;
          _isPrivate = SocialState().currentUser.isPrivate;
        }
      });
    }
  }

  Future<void> _checkFollowingStatus() async {
    try {
      final profile = await _socialService.getProfile(widget.user.username);
      final posts = await _socialService.getUserPosts(widget.user.username);

      if (mounted) {
        setState(() {
          _restricted = profile['restricted'] == true;
          _displayName =
              (profile['name'] ?? profile['username'] ?? _displayName)
                  .toString();
          _bio = (profile['bio'] ?? '').toString().trim();
          _sport = (profile['sport'] ?? '').toString().trim();
          _userImage =
              (profile['imagePath'] ?? profile['userImage'] ?? _userImage)
                  .toString();
          isFollowing = profile['isFollowing'] == true;
          isRequested = profile['isRequested'] == true ||
              SocialState().isFollowRequested(widget.user.username);
          _isPrivate = profile['isPrivate'] ?? widget.user.isPrivate;
          followersCount = profile['followersCount'] ?? widget.user.followers;
          followingCount = profile['followingCount'] ?? widget.user.following;
          postsCount = profile['postsCount'] ?? widget.user.posts;
          _userPosts = posts;
          isLoading = false;
        });
        SocialState().updateFollowStatus(widget.user.username, isFollowing);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _restricted = true;
          followersCount = widget.user.followers;
          followingCount = widget.user.following;
          postsCount = widget.user.posts;
          isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    final oldFollow = isFollowing;
    final oldFollowers = followersCount;

    try {
      if (!oldFollow) {
        if (_isPrivate) {
          // Si es privada, enviamos solicitud
          await _socialService.followUser(widget.user.username);
          SocialState().setFollowRequested(widget.user.username, true);
          SocialState().addLocalNotification(
            SocialState().currentUser.username,
            'ha solicitado seguirte',
            'follow_request',
            targetUser: widget.user.username,
          );
          if (mounted) {
            setState(() {
              isFollowing = false;
              isRequested = true;
            });
          }
        } else {
          final result = await _socialService.followUser(widget.user.username);
          final status = result['status'] ?? 'accepted';

          if (status == 'pending') {
            SocialState().setFollowRequested(widget.user.username, true);
            if (mounted) {
              setState(() {
                isFollowing = false;
                isRequested = true;
              });
            }
          } else {
            SocialState().updateFollowStatus(widget.user.username, true);
            if (mounted) {
              setState(() {
                isFollowing = true;
                isRequested = false;
                followersCount++;
              });
            }
          }
        }
      } else {
        await _socialService.unfollowUser(widget.user.username);
        SocialState().updateFollowStatus(widget.user.username, false);
        SocialState().setFollowRequested(widget.user.username, false);
        if (mounted) {
          setState(() {
            isFollowing = false;
            isRequested = false;
            followersCount--;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isFollowing = oldFollow;
          followersCount = oldFollowers;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final t = FitconnectLocalizations.of(context);
    final isSelf = widget.user.username == SocialState().currentUser.username;
    return Scaffold(
      backgroundColor: FeedPalette.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 24),
                if (!_restricted && (!_isPrivate || isFollowing || isSelf))
                  _buildHighlightsSection(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_restricted && !isSelf)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 80,
                    horizontal: 40,
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.block, size: 72, color: FeedPalette.muted),
                      const SizedBox(height: 24),
                      Text(
                        t.profileRestrictedBlocked,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: FeedPalette.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t.profileRestrictedBlockedHint,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: FeedPalette.muted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_isPrivate && !isFollowing && !isSelf)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 80,
                    horizontal: 40,
                  ),
                  child: Column(
                    children: [
                      // Logo de FitConnect Grande
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              FeedPalette.accent,
                              FeedPalette.accent.withValues(alpha: 0.8),
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: FeedPalette.accent.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.fitness_center_rounded,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'PERFIL PRIVADO',
                        style: TextStyle(
                          color: FeedPalette.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Solo los seguidores aprobados pueden ver\nlas publicaciones y actividad de @${widget.user.username}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: FeedPalette.muted,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: FeedPalette.surface,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: FeedPalette.accent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: FeedPalette.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Contenido Protegido',
                              style: TextStyle(
                                color: FeedPalette.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (!_restricted) ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: FeedPalette.accent,
                  unselectedLabelColor: FeedPalette.muted,
                  indicatorColor: FeedPalette.accent,
                  indicatorWeight: 3,
                  onTap: (index) => setState(() {}),
                  tabs: [
                    const Tab(icon: Icon(Icons.grid_on_rounded)),
                    widget.user.username == SocialState().currentUser.username
                        ? const Tab(icon: Icon(Icons.bookmark_border))
                        : const Tab(icon: Icon(Icons.assignment_ind_outlined)),
                  ],
                ),
              ),
            ),
            _buildGridView(),
          ],
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: FeedPalette.background,
      toolbarHeight: 82,
      flexibleSpace: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _displayName,
            style: TextStyle(
              color: FeedPalette.text,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.6,
            ),
          ),
          Text(
            '@${widget.user.username}',
            style: TextStyle(
              color: FeedPalette.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
      leading: IconButton(
        tooltip: 'Volver',
        icon: Icon(Icons.arrow_back_rounded, color: FeedPalette.text, size: 24),
        onPressed: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          }
        },
      ),
      actions: [
        if (widget.user.username != SocialState().currentUser.username)
          IconButton(
            icon: Icon(Icons.more_horiz, color: FeedPalette.text),
            onPressed: _showProfileOptions,
          ),
      ],
    );
  }

  void _showProfileOptions() {
    final isAdmin = AuthService().isAdmin;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
            if (isAdmin)
              ListTile(
                leading: const Icon(
                  Icons.person_off_outlined,
                  color: Colors.red,
                ),
                title: Text(
                  'Eliminar cuenta de ${widget.user.username}',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteAccount();
                },
              ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: const Text(
                'Bloquear usuario',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmBlockUser();
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined, color: Colors.red),
              title: const Text(
                'Reportar usuario',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reporte enviado')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          'Esta accion borrara la cuenta de ${widget.user.username} de forma permanente. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _adminService.deleteUser(username: widget.user.username);
                await SocialState().syncPosts();
                await SocialState().syncCurrentUser();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Cuenta de ${widget.user.username} eliminada por administracion.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo eliminar la cuenta: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockUser() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear usuario'),
        content: Text(
          '¿Estás seguro de que quieres bloquear a ${widget.user.username}? No podrá enviarte mensajes ni ver tus publicaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _socialService.blockUser(widget.user.username);
                if (!mounted) return;
                setState(() => _restricted = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Has bloqueado a ${widget.user.username}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo bloquear: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Bloquear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: FeedPalette.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAvatar(),
              const Expanded(child: SizedBox()),
              _buildStatsRow(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _displayName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FeedPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _sport.isEmpty ? 'Sin deporte' : _sport,
              style: TextStyle(
                fontSize: 12,
                color: FeedPalette.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _bio.isEmpty ? 'Este usuario no ha añadido biografía.' : _bio,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: FeedPalette.text,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Builder(
      builder: (context) {
        final userStoriesRaw = SocialState()
            .allStorySlides
            .where((s) => s['username'] == widget.user.username)
            .toList();
        final hasStory = userStoriesRaw.isNotEmpty;
        final storyCount = userStoriesRaw.length;
        bool isViewed = true;
        if (hasStory) {
          for (var s in userStoriesRaw) {
            if (!SocialState().isStoryViewed(
              s['id'] ?? '',
              isOwn: widget.user.username == SocialState().currentUser.username,
            )) {
              isViewed = false;
              break;
            }
          }
        }

        final isSelf =
            widget.user.username == SocialState().currentUser.username;
        final avatarImage =
            isSelf && SocialState().currentUser.userImage.trim().isNotEmpty
                ? SocialState().currentUser.userImage
                : _userImage;

        return GestureDetector(
          onTap: () {
            if (hasStory) {
              final userStoryModels = userStoriesRaw
                  .map(
                    (s) => StoryModel(
                      id: s['id'] ?? '',
                      username: s['username'] ?? '',
                      userImage: s['userImage'] ?? '',
                      image: s['image'] ?? '',
                      isOwn: s['isOwn'] == 'true',
                      createdAt: DateTime.now(),
                      expiresAt: DateTime.now().add(const Duration(hours: 24)),
                      isExpired: false,
                    ),
                  )
                  .toList();

              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (pageContext, animation, secondaryAnimation) =>
                      StoryViewPage(
                    stories: userStoryModels,
                    initialIndex: 0,
                    onStoryViewed: (story) {
                      SocialState().markStoryAsViewed(
                        story.id,
                        isOwn: story.isOwn,
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  transitionsBuilder: (
                    transitionContext,
                    animation,
                    secondaryAnimation,
                    child,
                  ) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            }
          },
          child: StorySegmentRing(
            segmentCount: hasStory ? storyCount : 0,
            viewed: hasStory ? isViewed : true,
            size: 86,
            child: CircleAvatar(
              radius: 37,
              backgroundColor: FeedPalette.surfaceSoft,
              child: ClipOval(
                child: SmartImage(
                  imageUrl: avatarImage,
                  width: 74,
                  height: 74,
                  fit: BoxFit.cover,
                  errorWidget: Icon(Icons.person, color: FeedPalette.muted),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatItem('Posts', postsCount.toString()),
        const SizedBox(width: 20),
        _buildStatItem(
          'Seguidores',
          followersCount.toString(),
          ontap: (!widget.user.isPrivate ||
                  isFollowing ||
                  widget.user.username == SocialState().currentUser.username)
              ? () => _openUserList('Seguidores')
              : null,
        ),
        const SizedBox(width: 20),
        _buildStatItem(
          'Siguiendo',
          followingCount.toString(),
          ontap: (!widget.user.isPrivate ||
                  isFollowing ||
                  widget.user.username == SocialState().currentUser.username)
              ? () => _openUserList('Siguiendo')
              : null,
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, {VoidCallback? ontap}) {
    return GestureDetector(
      onTap: ontap,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: FeedPalette.muted)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    ButtonStyle compactAction(ButtonStyle base) {
      return base.copyWith(
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        ),
        minimumSize: WidgetStateProperty.all(const Size(0, 44)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    final followStyle = compactAction(
      isFollowing
          ? FeedPalette.softButtonStyle()
          : (isRequested
              ? FeedPalette.softButtonStyle()
              : FeedPalette.primaryButtonStyle()),
    );
    final messageStyle = compactAction(FeedPalette.softButtonStyle());

    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: isRequested && !isFollowing ? null : _toggleFollow,
            style: followStyle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isFollowing
                      ? Icons.check_rounded
                      : (isRequested
                          ? Icons.hourglass_empty_rounded
                          : Icons.person_add_alt_1),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isFollowing
                        ? 'Siguiendo'
                        : (isRequested ? 'Solicitado' : 'Seguir'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DirectChatPage(user: widget.user),
              ),
            ),
            style: messageStyle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Mensaje',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: FeedPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: IconButton(
            icon: Icon(Icons.share_outlined, size: 20, color: FeedPalette.text),
            onPressed: () {
              _showShareProfileToFollowingSheet(widget.user);
            },
            tooltip: 'Compartir perfil',
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightsSection() {
    final highlights = SocialState().getHighlightsForUser(widget.user.username);
    if (highlights.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: highlights.length,
        itemBuilder: (context, index) {
          final h = highlights[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HighlightViewer(
                  highlights: highlights,
                  initialHighlightIndex: index,
                  isOwnProfile: widget.user.username ==
                      SocialState().currentUser.username,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Column(
                children: [
                  StorySegmentRing(
                    segmentCount: h.storyImages.length,
                    viewed: false,
                    size: 70,
                    strokeWidth: 2.4,
                    child: CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(h.coverImage),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    h.title,
                    style: TextStyle(
                      color: FeedPalette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridView() {
    return AnimatedBuilder(
      animation: SocialState(),
      builder: (context, child) {
        final isOwnProfile =
            widget.user.username == SocialState().currentUser.username;
        final isSavedTab = _tabController.index == 1 && isOwnProfile;

        List<String> images = [];
        if (isSavedTab) {
          images = SocialState()
              .posts
              .where((p) => p.isBookmarked)
              .map((p) => p.postImage)
              .toList();
        } else {
          images = _userPosts.isNotEmpty
              ? _userPosts
                  .map((e) => (e['image'] ?? '').toString())
                  .where((image) => image.isNotEmpty)
                  .toList()
              : SocialState().getUniquePostsForUser(widget.user.username);

          // Sincronizar el contador de posts con el número real de imágenes mostradas
          if (postsCount != images.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => postsCount = images.length);
            });
          }
        }

        if (images.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: FeedPalette.panelDecoration(),
                child: Column(
                  children: [
                    Icon(
                      isSavedTab ? Icons.bookmark_border : Icons.grid_on,
                      size: 40,
                      color: FeedPalette.accent.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isSavedTab
                          ? 'No tienes publicaciones guardadas'
                          : 'No hay publicaciones',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: FeedPalette.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1.5,
              mainAxisSpacing: 1.5,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final isOwnProfile =
                  widget.user.username == SocialState().currentUser.username;
              final isSavedTab = _tabController.index == 1 && isOwnProfile;

              Post? post;
              if (isSavedTab) {
                post = SocialState()
                    .posts
                    .where((p) => p.isBookmarked)
                    .toList()[index];
              } else {
                final imageUrl = images[index];
                try {
                  post = SocialState().posts.firstWhere(
                        (p) =>
                            p.postImage == imageUrl &&
                            p.username == widget.user.username,
                      );
                } catch (_) {
                  post = Post(
                    id: 'temp_$index',
                    username: widget.user.username,
                    userImage: _userImage,
                    postImage: imageUrl,
                    likes: 0,
                    caption: '',
                    time: 'Ahora',
                    comments: [],
                  );
                }
              }

              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetailPage(post: post!),
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: FeedPalette.panelDecoration(
                    radius: 18,
                    color: FeedPalette.surface,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SmartImage(
                      imageUrl: post.postImage,
                      fit: BoxFit.cover,
                      errorWidget: Center(
                        child:
                            Icon(Icons.broken_image, color: FeedPalette.muted),
                      ),
                    ),
                  ),
                ),
              );
            }, childCount: images.length),
          ),
        );
      },
    );
  }

  void _openUserList(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserListPage(
          title: title,
          username: widget.user.username,
          fetchUsers: (u) => title == 'Seguidores'
              ? _socialService.getFollowers(u)
              : _socialService.getFollowing(u),
        ),
      ),
    );
  }
}

class _SliverTabDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabDelegate(this._tabBar);
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
  bool shouldRebuild(_SliverTabDelegate oldDelegate) => false;
}
