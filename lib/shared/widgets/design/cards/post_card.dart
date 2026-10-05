import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:rms/features/social/post_model.dart';
import 'package:rms/features/social/social_state.dart';
import 'package:rms/features/profile/user_profile_page.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rms/features/social/social_service.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/core/utils/url_utils.dart';
import 'package:rms/features/home/story_view.dart';
import 'package:rms/features/social/story_model.dart';
import 'package:rms/features/admin/admin_service.dart';
import 'package:rms/features/search/search_page.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:flutter/gestures.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onShare,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _likeController;
  late Animation<double> _scaleAnimation;
  bool _showHeartOverlay = false;

  bool get _isOwnPost =>
      widget.post.username == SocialState().currentUser.username;

  List<InlineSpan> _parseMentions(
      BuildContext context, String text, TextStyle baseStyle) {
    if (!text.contains('@')) return [TextSpan(text: text, style: baseStyle)];

    final List<InlineSpan> spans = [];
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final space = i == words.length - 1 ? '' : ' ';

      if (word.startsWith('@') && word.length > 1) {
        final username =
            word.substring(1).replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '');
        spans.add(TextSpan(
          text: '$word$space',
          style: baseStyle.copyWith(
            color: FeedPalette.accent,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchPage(initialQuery: username),
                ),
              );
            },
        ));
      } else {
        spans.add(TextSpan(text: '$word$space', style: baseStyle));
      }
    }
    return spans;
  }

  VideoPlayerController? _videoController;
  bool _isVideo = false;
  final AdminService _adminService = AdminService();
  bool get _isAdmin => AuthService().isAdmin;

  @override
  void initState() {
    super.initState();
    _likeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(_likeController);

    final url = widget.post.postImage.toLowerCase();
    _isVideo = url.contains('.mp4') || url.contains('.mov');
    if (_isVideo) {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(widget.post.postImage))
            ..initialize().then((_) {
              setState(() {});
              _videoController!.setLooping(true);
              _videoController!.setVolume(0); // Mute by default for feed
            });
    }
  }

  @override
  void dispose() {
    _likeController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleLike() {
    SocialState().toggleLike(widget.post.id).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    });
    widget.onLike?.call();
  }

  void _handleDoubleTapLike() {
    if (!widget.post.isLiked) {
      _handleLike();
    }
    setState(() => _showHeartOverlay = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeartOverlay = false);
    });
  }

  void _handleBookmark() {
    SocialState().toggleBookmark(widget.post.id).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.post.isBookmarked
                  ? 'Publicación guardada'
                  : 'Publicación eliminada de guardados',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    });
  }

  void _showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CommentsSheet(post: widget.post),
    );
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShareSheetDialog(post: widget.post),
    );
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (_isOwnPost || _isAdmin)
              _buildOptionTile(
                Icons.delete_outline,
                'Eliminar publicacion',
                Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeletePost();
                },
              ),
            if (!_isOwnPost) ...[
              if (_isAdmin)
                _buildOptionTile(
                  Icons.person_off_outlined,
                  'Eliminar cuenta de ${widget.post.username}',
                  Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteUser(widget.post.username);
                  },
                ),
              _buildOptionTile(
                Icons.report_outlined,
                'Reportar',
                Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),
              _buildOptionTile(
                Icons.person_remove_outlined,
                'Dejar de seguir',
                Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _handleUnfollow();
                },
              ),
            ],
            const Divider(),
            _buildOptionTile(
                Icons.bookmark_border, 'Guardar', FeedPalette.text),
            _buildOptionTile(Icons.qr_code, 'Código QR', FeedPalette.text),
            _buildOptionTile(
              Icons.info_outline,
              'Sobre esta cuenta',
              Colors.black,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteUser(String targetUsername) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Eliminar cuenta de usuario'),
        content: Text(
          'Esta accion borrara la cuenta de $targetUsername permanentemente. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _adminService.deleteUser(username: targetUsername);
                await SocialState().syncPosts();
                await SocialState().syncCurrentUser();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Cuenta de $targetUsername eliminada correctamente por administracion.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
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
            child: Text(
              'Eliminar cuenta',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePost() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Eliminar publicacion'),
        content: Text(
          'Esta accion borrara la publicacion de forma permanente. Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await SocialState().deletePost(widget.post.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Publicacion eliminada correctamente'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo eliminar la publicacion: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 15)),
      onTap: onTap ??
          () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$label seleccionado'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 1),
              ),
            );
          },
    );
  }

  void _showReportDialog() {
    final options = [
      'Contenido inapropiado',
      'Spam',
      'Acoso o bullying',
      'Información falsa',
      'Violencia',
      'Otros',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reportar publicación'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(options[index]),
                onTap: () {
                  SocialState()
                      .report(widget.post.id, 'post', options[index])
                      .then((_) {
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reporte enviado')),
                    );
                  }).catchError((e) {
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al reportar: $e')),
                    );
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _handleUnfollow() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dejar de seguir a ${widget.post.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              SocialState().unfollowUser(widget.post.username).then((_) {
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Has dejado de seguir a ${widget.post.username}',
                    ),
                  ),
                );
              });
            },
            child: Text(
              'Dejar de seguir',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: FeedPalette.isDark
              ? FeedPalette.accent.withValues(alpha: 0.4)
              : FeedPalette.border,
          width: FeedPalette.isDark ? 1.5 : 1,
        ),
        boxShadow: [
          if (FeedPalette.isDark)
            BoxShadow(
              color: FeedPalette.accent.withValues(alpha: 0.12),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Color(0xFF9A5A34).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final userStoriesRaw = SocialState()
                        .allStorySlides
                        .where((s) => s['username'] == widget.post.username)
                        .toList();
                    final hasStory = userStoriesRaw.isNotEmpty;
                    bool isViewed = true;
                    if (hasStory) {
                      for (var s in userStoriesRaw) {
                        if (!SocialState().isStoryViewed(
                          s['id'] ?? '',
                          isOwn: widget.post.username ==
                              SocialState().currentUser.username,
                        )) {
                          isViewed = false;
                          break;
                        }
                      }
                    }

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
                                  expiresAt: DateTime.now().add(
                                    const Duration(hours: 24),
                                  ),
                                  isExpired: false,
                                ),
                              )
                              .toList();

                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (
                                pageContext,
                                animation,
                                secondaryAnimation,
                              ) =>
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
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
                          });
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                user: UserProfile(
                                  username: widget.post.username,
                                  displayName: widget.post.username,
                                  userImage: widget.post.userImage,
                                  bio: 'Entrenando fuerte cada día! 💪',
                                  sport: widget.post.tags.isNotEmpty
                                      ? widget.post.tags.first.replaceAll(
                                          '#',
                                          '',
                                        )
                                      : 'Fitness',
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.all(hasStory ? 2 : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: (hasStory && !isViewed)
                              ? FeedPalette.storyGradient
                              : null,
                          color: (hasStory && isViewed)
                              ? Colors.grey.shade400
                              : null,
                        ),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: FeedPalette.surface,
                          child: ClipOval(
                            child: SmartImage(
                              imageUrl: widget.post.userImage,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorWidget: Icon(
                                Icons.person,
                                color: FeedPalette.muted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfilePage(
                          user: UserProfile(
                            username: widget.post.username,
                            displayName: widget.post.username,
                            userImage: widget.post.userImage,
                            bio: 'Entrenando fuerte cada día! 💪',
                            sport: widget.post.tags.isNotEmpty
                                ? widget.post.tags.first.replaceAll('#', '')
                                : 'Fitness',
                          ),
                        ),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.post.username,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: FeedPalette.text,
                        ),
                      ),
                      if (widget.post.tags.isNotEmpty)
                        Text(
                          widget.post.tags.first,
                          style: TextStyle(
                            color: FeedPalette.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.more_horiz, size: 20),
                  onPressed: _showPostOptions,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          if (widget.post.postImage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: GestureDetector(
                  onDoubleTap: _handleDoubleTapLike,
                  onTap: () {
                    if (_isVideo && _videoController != null) {
                      setState(() {
                        _videoController!.value.isPlaying
                            ? _videoController!.pause()
                            : _videoController!.play();
                      });
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: _isVideo
                            ? (_videoController != null &&
                                    _videoController!.value.isInitialized
                                ? VideoPlayer(_videoController!)
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ))
                            : SmartImage(
                                imageUrl: widget.post.postImage,
                                fit: BoxFit.cover,
                                placeholder: Container(
                                  color: Color(0xFFF2E6DC),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: Container(
                                  color: Color(0xFFF7EFE7),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Colors.grey.shade400,
                                          size: 40,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Imagen no disponible',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (_isVideo &&
                          _videoController != null &&
                          !_videoController!.value.isPlaying)
                        Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 60,
                        ),
                      AnimatedOpacity(
                        opacity: _showHeartOverlay ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 400),
                          tween: Tween(
                            begin: 0.0,
                            end: _showHeartOverlay ? 1.0 : 0.0,
                          ),
                          curve: Curves.elasticOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Icon(
                                Icons.favorite,
                                color: Colors.white,
                                size: 100,
                                shadows: [
                                  Shadow(blurRadius: 30, color: Colors.black45),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Actions
          Row(
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: IconButton(
                  icon: Icon(
                    widget.post.isLiked
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: widget.post.isLiked ? Colors.red : FeedPalette.text,
                  ),
                  onPressed: _handleLike,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chat_bubble_outline,
                  color: FeedPalette.text,
                ),
                onPressed: _showComments,
              ),
              IconButton(
                icon: Icon(Icons.send_outlined, color: Color(0xFF241A14)),
                onPressed: _showShareSheet,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  widget.post.isBookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: FeedPalette.text,
                ),
                onPressed: _handleBookmark,
              ),
            ],
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.post.likes} Me gusta',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: FeedPalette.text,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: FeedPalette.text,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: '${widget.post.username} ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: FeedPalette.text,
                        ),
                      ),
                      ..._parseMentions(
                        context,
                        widget.post.caption,
                        TextStyle(color: FeedPalette.text, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // View comments link
                if (widget.post.comments.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _showComments,
                    child: Text(
                      'Ver los ${widget.post.comments.length} comentarios',
                      style: TextStyle(
                        color: FeedPalette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (widget.post.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: widget.post.tags
                        .map(
                          (tag) => GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      SearchPage(initialQuery: tag),
                                ),
                              );
                            },
                            child: Text(
                              tag,
                              style: TextStyle(
                                color: Color(0xFFD4632B),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  widget.post.time,
                  style: TextStyle(
                    color: Color(0xFF8D7B6F),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Comments Bottom Sheet ---
class _CommentsSheet extends StatefulWidget {
  final Post post;
  const _CommentsSheet({required this.post});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _showMentions = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _commentController.addListener(_onCommentChanged);
  }

  void _loadUsers() async {
    try {
      final users = await SocialService().getAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = users;
        });
      }
    } catch (_) {}
  }

  void _onCommentChanged() {
    final text = _commentController.text;
    final selection = _commentController.selection;

    if (selection.baseOffset > 0) {
      final beforeCursor = text.substring(0, selection.baseOffset);
      final lastAt = beforeCursor.lastIndexOf('@');

      if (lastAt != -1) {
        final query = beforeCursor.substring(lastAt + 1);
        // Only show if there's no space between @ and cursor or it's the start of a word
        bool isStartOfWord = lastAt == 0 || beforeCursor[lastAt - 1] == ' ';
        if (isStartOfWord && !query.contains(' ')) {
          setState(() {
            _showMentions = true;
            _filteredUsers = _allUsers.where((u) {
              final username = u['username']?.toString().toLowerCase() ?? '';
              final name = u['name']?.toString().toLowerCase() ?? '';
              final q = query.toLowerCase();
              return username.contains(q) || name.contains(q);
            }).toList();
          });
          return;
        }
      }
    }

    if (_showMentions) {
      setState(() {
        _showMentions = false;
      });
    }
  }

  void _applyMention(String username) {
    final text = _commentController.text;
    final selection = _commentController.selection;
    final beforeCursor = text.substring(0, selection.baseOffset);
    final afterCursor = text.substring(selection.baseOffset);
    final lastAt = beforeCursor.lastIndexOf('@');

    final newText =
        '${beforeCursor.substring(0, lastAt)}@$username $afterCursor';
    _commentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lastAt + username.length + 2),
    );
    setState(() {
      _showMentions = false;
    });
  }

  void _addComment() {
    if (_commentController.text.trim().isEmpty) return;
    final commentText = _commentController.text.trim();
    final newComment = Comment(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      userId: SocialState().currentUser.id?.toString() ?? '',
      username: SocialState().currentUser.username,
      userImage: SocialState().currentUser.userImage,
      text: commentText,
      time: 'Ahora',
    );

    SocialState().addComment(widget.post.id, newComment).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al comentar: $e')));
      }
    });

    _commentController.clear();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final canModerateAll = auth.isAdmin;
    final me = SocialState().currentUser.username.toLowerCase();
    final postOwner = widget.post.username.toLowerCase();
    final canManagePostComments = canModerateAll || me == postOwner;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Comentarios',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: FeedPalette.text,
            ),
          ),
          const Divider(),

          // Comments list
          Expanded(
            child: AnimatedBuilder(
              animation: SocialState(),
              builder: (context, child) {
                final currentPost = SocialState().posts.firstWhere(
                      (p) => p.id == widget.post.id,
                      orElse: () => widget.post,
                    );

                if (currentPost.comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aún no hay comentarios',
                          style:
                              TextStyle(color: FeedPalette.text, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sé el primero en comentar',
                          style:
                              TextStyle(color: FeedPalette.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  itemCount: currentPost.comments.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final comment = currentPost.comments[index];
                    final canDelete = canManagePostComments ||
                        comment.username.toLowerCase() == me;
                    return _CommentItem(
                      postId: currentPost.id,
                      comment: comment,
                      canDelete: canDelete,
                    );
                  },
                );
              },
            ),
          ),
          if (_showMentions && _filteredUsers.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: FeedPalette.surface,
                border: Border(top: BorderSide(color: FeedPalette.border)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  final username = user['username']?.toString() ?? '';
                  final name = user['name']?.toString() ?? '';
                  final image = user['userImage'] ?? user['imagePath'] ?? '';

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(
                        image.isNotEmpty
                            ? image
                            : 'https://ui-avatars.com/api/?name=$username',
                      ),
                    ),
                    title: Text(
                      username,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: FeedPalette.text,
                      ),
                    ),
                    subtitle: Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        color: FeedPalette.muted,
                      ),
                    ),
                    onTap: () => _applyMention(username),
                  );
                },
              ),
            ),

          // Input field
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: SmartImage(
                      imageUrl: SocialState().currentUser.userImage,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorWidget: const Icon(Icons.person, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Añade un comentario...',
                      hintStyle: TextStyle(color: FeedPalette.muted),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _addComment(),
                  ),
                ),
                TextButton(
                  onPressed: _addComment,
                  child: Text(
                    'Publicar',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentItem extends StatefulWidget {
  final String postId;
  final Comment comment;
  final bool canDelete;
  const _CommentItem({
    required this.postId,
    required this.comment,
    this.canDelete = false,
  });

  @override
  State<_CommentItem> createState() => _CommentItemState();
}

class _CommentItemState extends State<_CommentItem> {
  List<InlineSpan> _parseMentions(
      BuildContext context, String text, TextStyle baseStyle) {
    if (!text.contains('@')) return [TextSpan(text: text, style: baseStyle)];

    final List<InlineSpan> spans = [];
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final space = i == words.length - 1 ? '' : ' ';

      if (word.startsWith('@') && word.length > 1) {
        final username =
            word.substring(1).replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '');
        spans.add(TextSpan(
          text: '$word$space',
          style: baseStyle.copyWith(
            color: FeedPalette.accent,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchPage(initialQuery: username),
                ),
              );
            },
        ));
      } else {
        spans.add(TextSpan(text: '$word$space', style: baseStyle));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: 32,
              height: 32,
              child: SmartImage(
                imageUrl: widget.comment.userImage,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorWidget: const Icon(Icons.person, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: '${widget.comment.username} ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: FeedPalette.text,
                        ),
                      ),
                      ..._parseMentions(
                        context,
                        widget.comment.text,
                        TextStyle(color: FeedPalette.text, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.comment.time,
                  style: TextStyle(color: FeedPalette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              widget.comment.isLiked ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: widget.comment.isLiked ? Colors.red : Colors.grey,
            ),
            onPressed: () async {
              try {
                await SocialState()
                    .toggleCommentLike(widget.postId, widget.comment);
                if (mounted) setState(() {});
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo dar like: $e')),
                );
              }
            },
            visualDensity: VisualDensity.compact,
          ),
          if (widget.canDelete)
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.red,
              ),
              onPressed: () async {
                try {
                  await SocialState()
                      .deleteComment(widget.postId, widget.comment);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo eliminar: $e')),
                  );
                }
              },
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

// --- Instagram Style Share Sheet ---
class _ShareSheetDialog extends StatefulWidget {
  final Post post;
  const _ShareSheetDialog({required this.post});

  @override
  State<_ShareSheetDialog> createState() => _ShareSheetDialogState();
}

class _ShareSheetDialogState extends State<_ShareSheetDialog> {
  final SocialService _socialService = SocialService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  final Set<String> _selectedUsernames = {};
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _socialService.getAllUsers();
      users.removeWhere((u) => u['username'] == _authService.username);
      if (mounted) {
        setState(() {
          _users = users;
          _filteredUsers = users;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      final filtered = _users.where((u) {
        final username = u['username']?.toString().toLowerCase() ?? '';
        final name = u['name']?.toString().toLowerCase() ?? '';
        return username.contains(query.toLowerCase()) ||
            name.contains(query.toLowerCase());
      }).toList();
      _filteredUsers = filtered;
    });
  }

  void _toggleUser(String username) {
    setState(() {
      if (_selectedUsernames.contains(username)) {
        _selectedUsernames.remove(username);
      } else {
        _selectedUsernames.add(username);
      }
    });
  }

  Future<void> _sendToSelected() async {
    setState(() => _isSending = true);

    final payload = '[SHARED_POST]:${jsonEncode(widget.post.toSharePayload())}';

    for (final username in _selectedUsernames) {
      try {
        await _socialService.sendMessage(username, payload);
      } catch (_) {}
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Compartido con ${_selectedUsernames.length} persona${_selectedUsernames.length > 1 ? 's' : ''}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareToStory() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Compartiendo publicación en tu historia... 💫'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Encode post data to send to stories
      final payload = 'SHARED_POST:${jsonEncode(widget.post.toSharePayload())}';
      await _socialService.createStory(payload);

      messenger.showSnackBar(
        const SnackBar(
          content: Text('¡Añadido a tu historia! ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo añadir a la historia: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleAction(String action) async {
    final postUrl = "http://localhost:8081/#/home"; // Simulated post URL
    final messenger = ScaffoldMessenger.of(context);

    if (mounted) Navigator.pop(context);

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (action == 'whatsapp') {
        final url = Uri.parse(
          "https://wa.me/?text=Mira esta publicacion: $postUrl",
        );
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudo abrir WhatsApp')),
          );
        }
      } else if (action == 'link') {
        await Clipboard.setData(ClipboardData(text: postUrl));
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Enlace copiado al portapapeles ✅'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (action == 'share') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Opción de compartir nativa en desarrollo...'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (action == 'download') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Descargando imagen... 📥'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (action == 'story') {
        _shareToStory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: FeedPalette.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FeedPalette.searchField(
              hint: 'Buscar',
              onChanged: _filter,
              suffixIcon: Icon(
                Icons.person_add_outlined,
                color: FeedPalette.muted,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Users Grid
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.85,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                    ),
                    itemCount:
                        _filteredUsers.length > 6 ? 6 : _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isSelected = _selectedUsernames.contains(
                        user['username'],
                      );

                      return GestureDetector(
                        onTap: () => _toggleUser(user['username']),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 35,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: user['imagePath'] != null
                                      ? NetworkImage(
                                          UrlUtils.resolveFullUrl(
                                            user['imagePath'],
                                          ),
                                        )
                                      : null,
                                  child: user['imagePath'] == null
                                      ? Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                          size: 30,
                                        )
                                      : null,
                                ),
                                if (isSelected)
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.blue,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user['username'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isSelected ? Colors.blue : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          if (_selectedUsernames.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSending ? null : _sendToSelected,
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Enviar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildActionOption(
                      Icons.add_circle_outline,
                      'Añadir a\nhistoria',
                      () => _handleAction('story'),
                    ),
                    _buildActionOption(
                      Icons.message,
                      'WhatsApp',
                      () => _handleAction('whatsapp'),
                      color: Colors.green,
                    ),
                    _buildActionOption(
                      Icons.share,
                      'Compartir\nen...',
                      () => _handleAction('share'),
                    ),
                    _buildActionOption(
                      Icons.link,
                      'Copiar\nenlace',
                      () => _handleAction('link'),
                    ),
                    _buildActionOption(
                      Icons.download,
                      'Descargar',
                      () => _handleAction('download'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionOption(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    final effectiveColor = color ?? FeedPalette.text;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey.shade100,
              child: Icon(icon, color: effectiveColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: FeedPalette.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
