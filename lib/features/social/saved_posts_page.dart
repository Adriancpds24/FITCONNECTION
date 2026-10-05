import 'package:flutter/material.dart';

import '../../shared/themes/feed_palette.dart';
import '../../shared/widgets/design/cards/post_card.dart';
import 'post_model.dart';
import 'social_service.dart';

class SavedPostsPage extends StatefulWidget {
  const SavedPostsPage({super.key});

  @override
  State<SavedPostsPage> createState() => _SavedPostsPageState();
}

class _SavedPostsPageState extends State<SavedPostsPage> {
  final SocialService _socialService = SocialService();
  bool _isLoading = true;
  List<Post> _savedPosts = [];

  @override
  void initState() {
    super.initState();
    _loadSavedPosts();
  }

  Future<void> _loadSavedPosts() async {
    try {
      final savedData = await _socialService.getSavedPosts();

      final List<Post> loadedPosts = savedData.map((data) {
        return Post(
          id: data['id'].toString(),
          username: data['authorName'] ?? 'Usuario',
          userImage:
              'https://ui-avatars.com/api/?name=${data['authorName']}&background=random',
          postImage: data['image']?.toString() ?? '',
          likes: 0,
          caption: data['content'] ?? '',
          time: 'Hace un momento',
          isBookmarked: true,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _savedPosts = loadedPosts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar guardados: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        backgroundColor: FeedPalette.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: FeedPalette.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Publicaciones guardadas',
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                children: [
                  _buildSavedHero(),
                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: FeedPalette.accent,
                        ),
                      ),
                    )
                  else if (_savedPosts.isEmpty)
                    _buildEmptyState()
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _savedPosts.length,
                      itemBuilder: (context, index) {
                        return PostCard(post: _savedPosts[index]);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: FeedPalette.heroDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu coleccion',
            style: TextStyle(
              color: FeedPalette.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Guardados del feed',
            style: TextStyle(
              color: FeedPalette.text,
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Todo lo que quieras revisar luego queda agrupado aqui con la nueva estructura visual.',
            style: TextStyle(
              color: FeedPalette.muted,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(28),
      decoration: FeedPalette.panelDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.bookmark_border,
            size: 72,
            color: FeedPalette.accent.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes publicaciones guardadas',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Las publicaciones que guardes se veran aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: FeedPalette.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
