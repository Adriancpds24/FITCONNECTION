import 'package:flutter/material.dart';

import '../../shared/themes/feed_palette.dart';
import '../../shared/widgets/design/cards/post_card.dart';
import '../../shared/widgets/common/smart_image.dart';
import 'post_model.dart';
import 'social_state.dart';
import '../auth/auth_service.dart';

class PostDetailPage extends StatefulWidget {
  final Post post;

  const PostDetailPage({super.key, required this.post});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final socialState = SocialState();
  final TextEditingController _commentController = TextEditingController();
  bool _isSyncing = true;

  @override
  void initState() {
    super.initState();
    _loadPostDetails();
  }

  Future<void> _loadPostDetails() async {
    final postId = widget.post.id.trim();
    if (postId.isNotEmpty && !postId.startsWith('shared_')) {
      await socialState.syncPost(postId);
    }
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _addComment(String postId) {
    if (_commentController.text.trim().isEmpty) return;
    final commentText = _commentController.text.trim();

    final newComment = Comment(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      userId: socialState.currentUser.id?.toString() ?? '',
      username: socialState.currentUser.username,
      userImage: socialState.currentUser.userImage,
      text: commentText,
      time: 'Ahora',
    );

    socialState.addComment(postId, newComment).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al comentar: $e')));
      }
    });

    _commentController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: socialState,
        builder: (context, child) {
          final latestPost = socialState.getPost(widget.post.id) ?? widget.post;

          if (_isSyncing) {
            return Scaffold(
              backgroundColor: FeedPalette.background,
              appBar: AppBar(
                title: Text(
                  'Publicación',
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                centerTitle: true,
                backgroundColor: FeedPalette.background,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new,
                      color: FeedPalette.text, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Center(
                child: CircularProgressIndicator(color: FeedPalette.accent),
              ),
            );
          }

          return Scaffold(
            backgroundColor: FeedPalette.background,
            appBar: AppBar(
              title: Text(
                'Publicación',
                style: TextStyle(
                  color: FeedPalette.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              centerTitle: true,
              backgroundColor: FeedPalette.background,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new,
                    color: FeedPalette.text, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        children: [
                          PostCard(
                            post: latestPost,
                            onLike: () {},
                          ),
                          if (latestPost.comments.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              child: Text(
                                'Comentarios',
                                style: TextStyle(
                                  color: FeedPalette.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            ...latestPost.comments
                                .map((comment) => _buildCommentTile(comment)),
                          ] else ...[
                            const SizedBox(height: 40),
                            Center(
                              child: Column(
                                children: [
                                  Icon(Icons.chat_bubble_outline,
                                      size: 48,
                                      color: FeedPalette.muted
                                          .withValues(alpha: 0.3)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Aún no hay comentarios',
                                    style: TextStyle(color: FeedPalette.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _buildCommentInput(latestPost.id),
                  ],
                ),
              ),
            ),
          );
        });
  }

  Widget _buildCommentTile(Comment comment) {
    final me = socialState.currentUser.username.toLowerCase();
    final isAdmin = AuthService().isAdmin;
    final isPostOwner = widget.post.username.toLowerCase() == me;
    final canDelete =
        isAdmin || isPostOwner || comment.username.toLowerCase() == me;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: SmartImage(
                imageUrl: comment.userImage,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorWidget:
                    Icon(Icons.person, size: 18, color: FeedPalette.muted),
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
                    style: TextStyle(color: FeedPalette.text, fontSize: 14),
                    children: [
                      TextSpan(
                        text: '${comment.username} ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: comment.text),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comment.time,
                  style: TextStyle(color: FeedPalette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              comment.isLiked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: comment.isLiked ? Colors.red : FeedPalette.muted,
            ),
            onPressed: () async {
              try {
                await socialState.toggleCommentLike(widget.post.id, comment);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo dar like: $e')),
                );
              }
            },
          ),
          if (canDelete)
            IconButton(
              icon:
                  const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: () async {
                try {
                  await socialState.deleteComment(widget.post.id, comment);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo eliminar: $e')),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(String postId) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: SmartImage(
                imageUrl: socialState.currentUser.userImage,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorWidget:
                    Icon(Icons.person, size: 18, color: FeedPalette.muted),
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
                isDense: true,
              ),
              style: TextStyle(color: FeedPalette.text),
              onSubmitted: (_) => _addComment(postId),
            ),
          ),
          TextButton(
            onPressed: () => _addComment(postId),
            child: Text(
              'Publicar',
              style: TextStyle(
                color: FeedPalette.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
