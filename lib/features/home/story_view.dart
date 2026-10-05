import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/api_constants.dart';
import '../../core/utils/profile_avatar.dart';
import '../social/story_model.dart';
import '../social/post_model.dart';
import '../social/social_state.dart';
import '../profile/user_profile_page.dart';
import '../social/post_detail_page.dart';
import '../admin/admin_service.dart';
import '../auth/auth_service.dart';
import '../social/social_service.dart';
import '../../shared/widgets/common/smart_image.dart';

class StoryViewPage extends StatefulWidget {
  final List<StoryModel> stories;
  final int initialIndex;
  final ValueChanged<StoryModel>? onStoryViewed;

  const StoryViewPage({
    super.key,
    required this.stories,
    required this.initialIndex,
    this.onStoryViewed,
  });

  @override
  State<StoryViewPage> createState() => _StoryViewPageState();
}

class _StoryViewPageState extends State<StoryViewPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyStoryViewed(_currentIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onStoryFinished() {
    if (_currentIndex < widget.stories.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _onPreviousStory() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _notifyStoryViewed(int index) {
    if (index < 0 || index >= widget.stories.length) return;
    widget.onStoryViewed?.call(widget.stories[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.stories.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _notifyStoryViewed(index);
        },
        itemBuilder: (context, index) {
          return StoryItemView(
            story: widget.stories[index],
            storyIndex: index,
            totalStories: widget.stories.length,
            isActive: _currentIndex == index,
            onFinished: _onStoryFinished,
            onPrevious: _onPreviousStory,
          );
        },
      ),
    );
  }
}

class StoryItemView extends StatefulWidget {
  final StoryModel story;
  final int storyIndex;
  final int totalStories;
  final bool isActive;
  final VoidCallback onFinished;
  final VoidCallback onPrevious;
  const StoryItemView({
    super.key,
    required this.story,
    required this.storyIndex,
    required this.totalStories,
    required this.isActive,
    required this.onFinished,
    required this.onPrevious,
  });

  @override
  State<StoryItemView> createState() => _StoryItemViewState();
}

class _StoryItemViewState extends State<StoryItemView>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _isSharedPost = false;
  Post? _sharedPost;
  final AdminService _adminService = AdminService();

  @override
  void initState() {
    super.initState();
    final rawImage = widget.story.image ?? '';
    _isSharedPost = rawImage.startsWith('SHARED_POST:');

    if (_isSharedPost) {
      try {
        final jsonStr = rawImage.substring(12);
        final map = jsonDecode(jsonStr);
        _sharedPost = Post(
          id: map['id'].toString(),
          username: map['username'] ?? 'usuario',
          userImage: map['userImage'] ?? '',
          postImage: map['postImage'] ?? '',
          caption: map['caption'] ?? '',
          likes: map['likes'] ?? 0,
          time: 'Compartido',
        );
      } catch (e) {
        debugPrint('Error parsing shared post in story: $e');
        _isSharedPost = false;
      }
    }

    final url = _resolveStoryImage(widget.story.image);
    _isVideo = !_isSharedPost &&
        (url.toLowerCase().startsWith('data:video/') ||
            url.toLowerCase().contains('.mp4') ||
            url.toLowerCase().contains('.mov'));

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    if (_isVideo) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          setState(() {});
          if (widget.isActive) {
            _progressController.duration = _videoController!.value.duration;
            _videoController!.play();
            _progressController.forward();
          }
        });
    } else {
      if (widget.isActive) {
        _progressController.forward();
      }
    }

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });
  }

  void _handleLikeStory() {
    setState(() {
      widget.story.isLiked = !(widget.story.isLiked ?? false);
    });
  }

  void _showStoryOptions() {
    _progressController.stop();
    _videoController?.pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (widget.story.isOwn)
              ListTile(
                leading: const Icon(Icons.star_border, color: Colors.black),
                title: const Text('Destacar historia'),
                onTap: () {
                  Navigator.pop(context, 'highlight');
                },
              ),
            if (widget.story.isOwn || AuthService().isAdmin)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Eliminar historia',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final rootContext = context;
                  navigator.pop();
                  final shouldDelete = await showDialog<bool>(
                    context: rootContext,
                    builder: (context) => AlertDialog(
                      title: const Text('Eliminar historia'),
                      content: const Text(
                        '¿Estás seguro de que quieres eliminar esta historia?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (shouldDelete == true && mounted) {
                    try {
                      if (widget.story.isOwn) {
                        await SocialState().deleteStory(widget.story.id);
                      } else {
                        final storyId = int.tryParse(widget.story.id);
                        if (storyId == null) {
                          throw Exception('ID de historia invalido');
                        }
                        await _adminService.archiveStory(storyId);
                        await SocialState().syncStories();
                      }
                      navigator.pop();
                    } catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('Error al eliminar: $e')),
                      );
                    }
                  }
                },
              ),
            if (!widget.story.isOwn && AuthService().isAdmin)
              ListTile(
                leading: const Icon(
                  Icons.person_off_outlined,
                  color: Colors.red,
                ),
                title: Text(
                  'Eliminar cuenta de ${widget.story.username}',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final rootContext = context;
                  navigator.pop();
                  final shouldDelete = await showDialog<bool>(
                    context: rootContext,
                    builder: (context) => AlertDialog(
                      title: const Text('Eliminar cuenta de usuario'),
                      content: Text(
                        'Esta accion borrara la cuenta de ${widget.story.username}. ¿Deseas continuar?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Eliminar',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (shouldDelete == true && mounted) {
                    try {
                      await _adminService.deleteUser(
                        username: widget.story.username,
                      );
                      await SocialState().syncPosts();
                      await SocialState().syncCurrentUser();
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Cuenta de ${widget.story.username} eliminada correctamente por administracion.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      navigator.pop();
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('No se pudo eliminar la cuenta: $e'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
            if (!widget.story.isOwn &&
                SocialState().currentUser.username != 'admin')
              ListTile(
                leading: const Icon(Icons.report_outlined, color: Colors.black),
                title: const Text('Reportar historia'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reporte enviado')),
                  );
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    ).then((val) {
      if (val == 'highlight') {
        _showHighlightOptions();
        return;
      }
      if (mounted) {
        _progressController.forward();
        _videoController?.play();
      }
    });
  }

  void _showHighlightOptions() {
    _progressController.stop();
    _videoController?.pause();

    final highlights = SocialState().getHighlightsForUser(
      SocialState().currentUser.username,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Añadir a destacadas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: highlights.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _showCreateNewHighlightDialog();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black,
                                  width: 1.5,
                                ),
                              ),
                              child: const CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.add,
                                  color: Colors.black,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
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
                    onTap: () async {
                      Navigator.pop(context);
                      await SocialState().addStoryToHighlight(
                        h.id,
                        widget.story.image ?? '',
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('Añadida a ${h.title}')),
                        );
                        _progressController.forward();
                        _videoController?.play();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundImage: NetworkImage(h.coverImage),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            h.title,
                            style: const TextStyle(
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
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) {
        _progressController.forward();
        _videoController?.play();
      }
    });
  }

  void _showCreateNewHighlightDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva historia destacada'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(hintText: 'Título de la historia'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                _progressController.forward();
                _videoController?.play();
              }
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty) {
                Navigator.pop(context);
                try {
                  await SocialState().addHighlight(titleController.text, [
                    widget.story.image ?? '',
                  ]);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Añadida a nuevas destacadas'),
                      ),
                    );
                    _progressController.forward();
                    _videoController?.play();
                  }
                } catch (_) {}
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant StoryItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _videoController?.play();
      _progressController.forward(from: 0);
    } else if (!widget.isActive && oldWidget.isActive) {
      _videoController?.pause();
      _progressController.stop();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  String _resolveStoryImage(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1200&q=80';
    }
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    if (imagePath.startsWith('data:')) {
      return imagePath;
    }
    final apiOrigin = ApiConstants.apiHost.replaceFirst(RegExp(r'/api$'), '');
    return '$apiOrigin$imagePath';
  }

  String _formatElapsed(DateTime createdAt) {
    final delta = DateTime.now().difference(createdAt);
    if (delta.inMinutes < 1) return 'Ahora';
    if (delta.inHours < 1) return 'Hace ${delta.inMinutes} min';
    if (delta.inHours < 24) return 'Hace ${delta.inHours} h';
    return 'Hace ${delta.inDays} d';
  }

  void _pauseHold() {
    _progressController.stop();
    _videoController?.pause();
  }

  void _resumeHold() {
    if (!widget.isActive) return;
    _videoController?.play();
    if (_isVideo &&
        _videoController != null &&
        _videoController!.value.isInitialized) {
      final total = _videoController!.value.duration.inMilliseconds;
      final pos = _videoController!.value.position.inMilliseconds;
      if (total > 0) {
        _progressController.value = (pos / total).clamp(0.0, 1.0);
      }
    }
    _progressController.forward();
  }

  Future<void> _openStoryReplySheet() async {
    if (widget.story.isOwn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes responderte a ti mismo desde aqui.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _pauseHold();
    final controller = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Responder a ${widget.story.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      try {
                        await SocialService().sendMessage(
                          widget.story.username,
                          _buildStoryReplyContent(text: text),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mensaje enviado'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(
                            ctx,
                          ).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                    child: const Text('Enviar'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      controller.dispose();
      if (mounted) _resumeHold();
    }
  }

  Future<void> _sendReactionEmoji(String emoji) async {
    if (widget.story.isOwn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reaccion: $emoji'),
          duration: const Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await SocialService().sendMessage(
        widget.story.username,
        _buildStoryReplyContent(emoji: emoji),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enviaste $emoji a ${widget.story.username}'),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la reaccion: $e')),
      );
    }
  }

  String _buildStoryReplyContent({String? text, String? emoji}) {
    final payload = {
      'story': {
        'id': widget.story.id,
        'username': widget.story.username,
        'image': widget.story.image ?? '',
        'createdAt': widget.story.createdAt.toIso8601String(),
        'expiresAt': widget.story.expiresAt.toIso8601String(),
      },
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (emoji != null && emoji.trim().isNotEmpty) 'emoji': emoji.trim(),
    };
    return '[STORY_REPLY]:${jsonEncode(payload)}';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _resolveStoryImage(widget.story.image);
    final avatarUrl = ProfileAvatar.forStory(widget.story);
    final topPad = MediaQuery.paddingOf(context).top + 52;
    const bottomReserve = 200.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        _isSharedPost
            ? Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    // Blurred background image
                    if (_sharedPost?.postImage != null)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.5,
                          child: SmartImage(
                            imageUrl: _sharedPost!.postImage,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(color: Colors.black12),
                      ),
                    ),
                    // The Post Sticker
                    Center(
                      child: Transform.rotate(
                        angle: -0.05, // Slight rotation for sticker look
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: GestureDetector(
                            onTap: () {
                              _progressController.stop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PostDetailPage(post: _sharedPost!),
                                ),
                              ).then((_) {
                                if (mounted) _progressController.forward();
                              });
                            },
                            child: Hero(
                              tag: 'shared_post_${_sharedPost!.id}',
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Header of the sticker
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      color: Colors.white,
                                      child: Row(
                                        children: [
                                          ClipOval(
                                            child: SmartImage(
                                              imageUrl: _sharedPost!.userImage,
                                              width: 28,
                                              height: 28,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _sharedPost!.username,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Image of the sticker
                                    AspectRatio(
                                      aspectRatio: 1,
                                      child: SmartImage(
                                        imageUrl: _sharedPost!.postImage,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    // Small footer to invite clicking
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        border: Border(
                                          top: BorderSide(
                                            color: Colors.grey.shade100,
                                          ),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.touch_app,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Ver publicación',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : _isVideo
                ? (_videoController != null &&
                        _videoController!.value.isInitialized
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()))
                : SmartImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 44,
                      ),
                    ),
                  ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: topPad, bottom: bottomReserve),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onPrevious,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _pauseHold(),
                    onPointerUp: (_) => _resumeHold(),
                    onPointerCancel: (_) => _resumeHold(),
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onFinished,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return Row(
                      children: List.generate(widget.totalStories, (index) {
                        final value = index < widget.storyIndex
                            ? 1.0
                            : index == widget.storyIndex
                                ? _progressController.value
                                : 0.0;
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(
                              right: index == widget.totalStories - 1 ? 0 : 4,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: value,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                minHeight: 3,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _progressController.stop();
                          _videoController?.pause();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                user: UserProfile(
                                  username: widget.story.username,
                                  displayName: widget.story.username,
                                  userImage: widget.story.userImage ?? '',
                                  bio: 'Cargando perfil...',
                                  sport: 'Fitness',
                                  followers: 0,
                                  following: 0,
                                  posts: 0,
                                ),
                              ),
                            ),
                          ).then((_) {
                            _progressController.forward();
                            _videoController?.play();
                          });
                        },
                        child: Row(
                          children: [
                            ClipOval(
                              child: SmartImage(
                                imageUrl: avatarUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorWidget: const Icon(
                                  Icons.person,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.story.username,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    _formatElapsed(widget.story.createdAt),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (widget.story.isOwn || AuthService().isAdmin)
                      IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.white),
                        onPressed: _showStoryOptions,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Reactions (Instagram style)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            ...[
                              '🔥',
                              '👏',
                              '❤️',
                              '😮',
                              '😢',
                              '😂',
                              '🙌',
                              '😍',
                            ].map(
                              (emoji) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: InkWell(
                                  onTap: () => _sendReactionEmoji(emoji),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _openStoryReplySheet,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              child: Text(
                                widget.story.isOwn
                                    ? 'Mensajes en tu bandeja'
                                    : 'Enviar mensaje...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: Icon(
                            (widget.story.isLiked ?? false)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: (widget.story.isLiked ?? false)
                                ? Colors.red
                                : Colors.white,
                            size: 28,
                          ),
                          onPressed: _handleLikeStory,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.send_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () {
                            _progressController.stop();
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (context) => Container(
                                padding: const EdgeInsets.all(24),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Compartir historia',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    ListTile(
                                      leading: const Icon(Icons.copy),
                                      title: const Text('Copiar enlace'),
                                      onTap: () => Navigator.pop(context),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.share),
                                      title: const Text('Otras aplicaciones'),
                                      onTap: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                              ),
                            ).then((_) => _progressController.forward());
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
