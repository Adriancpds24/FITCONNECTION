import 'package:flutter/material.dart';
import '../social/post_model.dart';
import '../profile/user_profile_page.dart';
import '../social/social_service.dart';
import '../social/social_state.dart';
import '../../shared/themes/feed_palette.dart';
import '../../shared/widgets/common/smart_image.dart';
import '../../shared/widgets/design/cards/post_card.dart';

class SearchPage extends StatefulWidget {
  final String? initialQuery;
  const SearchPage({super.key, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeTab = 'Todos';
  final SocialService _socialService = SocialService();
  final SocialState _socialState = SocialState();

  List<UserProfile> _allUsers = [];
  bool _isLoading = true;

  final List<String> _discoveryCategories = [
    'Todos',
    'Usuarios',
    'Hashtags',
    'Desafíos',
    'Rutinas',
    'Grupos',
  ];

  final List<Map<String, dynamic>> _trendingHashtags = [
    {'tag': '#LegDay', 'posts': '12.5k'},
    {'tag': '#MaratonMadrid', 'posts': '8.2k'},
    {'tag': '#YogaMorning', 'posts': '5.4k'},
    {'tag': '#CrossFitGames', 'posts': '25k'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _searchQuery = widget.initialQuery!;
      _searchController.text = widget.initialQuery!;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final usersJson = await _socialService.getAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = usersJson.map((j) => UserProfile.fromJson(j)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading search data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<UserProfile> get _filteredUsers {
    if (_searchQuery.isEmpty) return _allUsers.take(10).toList();
    return _allUsers
        .where(
          (user) =>
              user.username.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ||
              user.displayName.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                children: [
                  _buildHeader(),
                  _buildTabBar(),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _searchQuery.isEmpty
                            ? _buildDiscoveryEngine()
                            : _buildSearchResults(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close_rounded,
                  color: FeedPalette.text,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Text(
                'Descubrir',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                  color: FeedPalette.text,
                  letterSpacing: -1,
                ),
              ),
              const Spacer(),
              if (_activeTab == 'Desafíos')
                GestureDetector(
                  onTap: _showCreateChallenge,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: FeedPalette.accent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: FeedPalette.accent.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 18),
                        const SizedBox(width: 4),
                        const Text(
                          'Nuevo Reto',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: FeedPalette.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: TextStyle(color: FeedPalette.text),
                    decoration: InputDecoration(
                      hintText: 'Usuarios, hashtags, rutinas...',
                      hintStyle: TextStyle(color: FeedPalette.muted),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: FeedPalette.accent,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        key: const ValueKey('search_tabs_list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _discoveryCategories.length,
        itemBuilder: (context, index) {
          final cat = _discoveryCategories[index];
          final isSelected = _activeTab == cat;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: isSelected ? FeedPalette.accent : FeedPalette.surface,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSelected ? FeedPalette.accent : FeedPalette.border,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: FeedPalette.accent.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: Center(
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? Colors.white : FeedPalette.text,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDiscoveryEngine() {
    return ListView(
      key: const ValueKey('discovery_engine_list'),
      padding: const EdgeInsets.all(20),
      children: [
        if (_activeTab == 'Usuarios' || _activeTab == 'Todos') ...[
          _buildSectionTitle('Sugerencias para ti', Icons.auto_awesome),
          const SizedBox(height: 16),
          SizedBox(
            height: 196,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              primary: false, // Evita conflictos de controlador
              itemCount: _allUsers.length.clamp(0, 5),
              itemBuilder: (context, index) =>
                  _buildSuggestionCard(_allUsers[index]),
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (_activeTab == 'Hashtags' || _activeTab == 'Todos') ...[
          _buildSectionTitle('Tendencias hoy', Icons.trending_up),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                _trendingHashtags.map((h) => _buildHashtagCard(h)).toList(),
          ),
          const SizedBox(height: 32),
        ],
        if (_activeTab == 'Desafíos' || _activeTab == 'Todos') ...[
          _buildSectionTitle('Desafíos destacados', Icons.emoji_events),
          const SizedBox(height: 16),
          ..._socialState.challenges.map((c) => _buildChallengeCard(c)),
        ],
        if (_activeTab == 'Rutinas' || _activeTab == 'Todos') ...[
          _buildSectionTitle('Rutinas de la comunidad', Icons.fitness_center),
          const SizedBox(height: 16),
          ..._socialState.routines.map((r) => _buildRoutineCard(r)),
          const SizedBox(height: 32),
        ],
        if (_activeTab == 'Grupos' || _activeTab == 'Todos') ...[
          _buildSectionTitle('Grupos populares', Icons.groups_rounded),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _socialState.groups.length,
            itemBuilder: (context, index) =>
                _buildGroupCard(_socialState.groups[index]),
          ),
        ],
      ],
    );
  }

  void _showCreateChallenge() {
    final titleController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: FeedPalette.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: FeedPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Nuevo Desafío',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: FeedPalette.text,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: titleController,
              decoration: FeedPalette.inputDecoration(
                hint: 'Nombre del desafío (ej. 100 FLEXIONES)',
                icon: Icons.emoji_events,
              ).copyWith(
                filled: true,
                fillColor: FeedPalette.background.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isNotEmpty) {
                    setState(() {
                      _socialState.createChallenge(
                        title,
                        'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800',
                      );
                    });
                    Navigator.pop(ctx);
                  }
                },
                style: FeedPalette.primaryButtonStyle(radius: 16),
                child: const Text('Crear y Publicar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: FeedPalette.accent),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: FeedPalette.text,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionCard(UserProfile user) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfilePage(user: user)),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(16),
        decoration: FeedPalette.panelDecoration(radius: 24),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: FeedPalette.surfaceSoft,
              child: ClipOval(
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: SmartImage(
                    imageUrl: user.userImage,
                    fit: BoxFit.cover,
                    errorWidget: Icon(Icons.person, color: FeedPalette.muted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user.displayName,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: FeedPalette.text,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              user.sport,
              style: TextStyle(color: FeedPalette.muted, fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            _buildMiniFollowButton(user),
          ],
        ),
      ),
    );
  }

  Widget _buildHashtagCard(Map<String, dynamic> h) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _searchQuery = h['tag'];
          _searchController.text = h['tag'];
          _activeTab = 'Hashtags';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: FeedPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FeedPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              h['tag'],
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: FeedPalette.text,
              ),
            ),
            Text(
              '${h['posts']} publicaciones',
              style: TextStyle(color: FeedPalette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineCard(Map<String, dynamic> r) {
    return GestureDetector(
      onTap: () => _showRoutineDetails(r),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: FeedPalette.panelDecoration(radius: 24),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(r['image']),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['title'],
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: FeedPalette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 14, color: FeedPalette.muted),
                        const SizedBox(width: 4),
                        Text(r['time'],
                            style: TextStyle(
                                color: FeedPalette.muted, fontSize: 12)),
                        const SizedBox(width: 12),
                        Icon(Icons.bolt, size: 14, color: FeedPalette.accent),
                        const SizedBox(width: 4),
                        Text(r['difficulty'],
                            style: TextStyle(
                                color: FeedPalette.muted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Por ${r['author']}',
                      style: TextStyle(
                        color: FeedPalette.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: FeedPalette.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> g) {
    return GestureDetector(
      onTap: () => _showGroupDetails(g),
      child: Container(
        decoration: FeedPalette.panelDecoration(radius: 24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(g['image']),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: FeedPalette.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      g['category'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: FeedPalette.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${g['members']} miembros',
                    style: TextStyle(
                      color: FeedPalette.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChallengeCard(Map<String, dynamic> c) {
    return GestureDetector(
      onTap: () => _showChallengeDetails(c),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: FeedPalette.heroDecoration(radius: 24),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                c['image'],
                fit: BoxFit.cover,
                color: Colors.white.withValues(alpha: 0.1),
                colorBlendMode: BlendMode.dstATop,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          c['title'],
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            color: FeedPalette.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${c['participants']} atletas activos',
                          style: TextStyle(
                            color: FeedPalette.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildJoinButton(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinButton(Map<String, dynamic> c) {
    final bool isJoined = c['isJoined'] ?? false;
    return ElevatedButton(
      onPressed: isJoined
          ? null
          : () {
              setState(() => _socialState.joinChallenge(c['id']));
              _showChallengeDetails(c);
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: isJoined
            ? Colors.green.withValues(alpha: 0.2)
            : FeedPalette.surface,
        foregroundColor: isJoined ? Colors.green : FeedPalette.text,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(isJoined ? 'Unido' : 'Unirse'),
    );
  }

  void _showChallengeDetails(Map<String, dynamic> c) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ChallengeDetails',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return ListenableBuilder(
          listenable: _socialState,
          builder: (context, child) {
            final bool isJoined = c['isJoined'] ?? false;
            return Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildChallengeHero(c),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildChallengeHeader(c),
                              const SizedBox(height: 16),
                              _buildChallengeDescription(c),
                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),
                              _buildChallengeStats(c),
                              const SizedBox(height: 32),
                              if (!isJoined)
                                _buildStartButton(c)
                              else
                                _buildJoinedProgress(c),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  Widget _buildChallengeHero(Map<String, dynamic> c) {
    return Stack(
      children: [
        Image.network(
          c['image'],
          height: 220,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.4),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FeedPalette.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Nivel: ${c['difficulty'] ?? 'Pro'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeHeader(Map<String, dynamic> c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c['title'].toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 28,
            color: FeedPalette.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Por FitConnect Community',
          style: TextStyle(
            color: FeedPalette.accent,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeDescription(Map<String, dynamic> c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿EN QUÉ CONSISTE?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: FeedPalette.muted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          c['description'] ??
              'Este desafío pondrá a prueba tu disciplina. Deberás completar la rutina diaria asignada durante el periodo establecido para desbloquear la medalla de honor.',
          style: TextStyle(
            color: FeedPalette.text.withValues(alpha: 0.9),
            fontSize: 15,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeStats(Map<String, dynamic> c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(Icons.people_alt, '${c['participants']}', 'Atletas'),
        _buildStatItem(Icons.timer_outlined, '30', 'Días'),
        _buildStatItem(Icons.workspace_premium, '+500', 'XP'),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: FeedPalette.muted, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: FeedPalette.text,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: FeedPalette.muted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildStartButton(Map<String, dynamic> c) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _handleJoinChallenge(c),
        style: FeedPalette.primaryButtonStyle(radius: 18).copyWith(
          padding:
              WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 18)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'ACEPTAR DESAFÍO',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleJoinChallenge(Map<String, dynamic> c) {
    setState(() => _socialState.joinChallenge(c['id']));

    // Cerrar detalles y mostrar animación de éxito
    Navigator.pop(context);
    _showSuccessAnimation(c);
  }

  void _showSuccessAnimation(Map<String, dynamic> c) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 1),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: FeedPalette.accent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: FeedPalette.accent.withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: Colors.amber,
                        size: 100,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: anim1,
                child: Column(
                  children: [
                    Text(
                      '¡DESAFÍO ACTIVADO!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Has empezado: ${c['title']}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(
                        '¡A DARLE CAÑA!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJoinedProgress(Map<String, dynamic> c) {
    int currentDay = 1;
    double progress = 0.05;

    if (c['joinedAt'] != null) {
      try {
        final joinedDate = DateTime.parse(c['joinedAt']);
        currentDay = DateTime.now().difference(joinedDate).inDays + 1;
        if (currentDay < 1) currentDay = 1;
        if (currentDay > 30) currentDay = 30;
        progress = currentDay / 30;
      } catch (e) {
        debugPrint('Error calculating progress: $e');
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'DESAFÍO EN CURSO',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 8),
          Text(
            'Día $currentDay de 30 · ¡Sigue así!',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FeedPalette.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_activeTab == 'Hashtags') {
      final tagResults = _socialState.posts
          .where(
            (p) =>
                p.caption.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                p.tags.any(
                  (t) => t.toLowerCase().contains(_searchQuery.toLowerCase()),
                ),
          )
          .toList();

      if (tagResults.isEmpty) {
        return const Center(
          child: Text('No se encontraron publicaciones con ese hashtag'),
        );
      }

      return ListView.builder(
        key: const ValueKey('tag_results_feed'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        primary: false,
        itemCount: tagResults.length,
        itemBuilder: (context, index) {
          final post = tagResults[index];
          return PostCard(
            post: post,
            onLike: () => setState(() {}),
          );
        },
      );
    }

    if (_activeTab == 'Rutinas') {
      final routines = _socialState.routines
          .where((r) =>
              r['title'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
              r['author'].toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
      if (routines.isEmpty) {
        return const Center(child: Text('No se encontraron rutinas'));
      }
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: routines.length,
        itemBuilder: (context, index) => _buildRoutineCard(routines[index]),
      );
    }

    if (_activeTab == 'Grupos') {
      final groups = _socialState.groups
          .where((g) =>
              g['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
              g['category'].toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
      if (groups.isEmpty) {
        return const Center(child: Text('No se encontraron grupos'));
      }
      return GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: groups.length,
        itemBuilder: (context, index) => _buildGroupCard(groups[index]),
      );
    }

    if (_activeTab != 'Usuarios' && _activeTab != 'Todos') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rocket_launch_rounded,
              size: 60,
              color: FeedPalette.border,
            ),
            const SizedBox(height: 16),
            Text(
              'Buscando $_activeTab para "$_searchQuery"...',
              style: TextStyle(color: FeedPalette.muted),
            ),
          ],
        ),
      );
    }

    final results = _filteredUsers;
    if (results.isEmpty) {
      return const Center(child: Text('No se encontraron resultados'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      primary: false,
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildRichUserCard(results[index]),
    );
  }

  bool _isCompactSearchLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 420;

  double _userNameFontSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 340) return 12;
    if (width < 380) return 13;
    if (width < 420) return 14;
    if (width < 480) return 16;
    return 17;
  }

  Widget _buildSearchUserAvatar(UserProfile user, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: FeedPalette.surfaceSoft,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: SmartImage(
            imageUrl: user.userImage,
            fit: BoxFit.cover,
            errorWidget: Icon(Icons.person, color: FeedPalette.muted),
          ),
        ),
      ),
    );
  }

  Widget _buildRichUserCardHeader(UserProfile user) {
    final nameSize = _userNameFontSize(context);
    final compact = _isCompactSearchLayout(context);
    final avatarRadius = compact ? 26.0 : 30.0;
    final nameStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: nameSize,
      letterSpacing: -0.5,
      height: 1.1,
      color: FeedPalette.text,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchUserAvatar(user, avatarRadius),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth,
                              ),
                              child: Text(
                                user.displayName,
                                maxLines: 1,
                                softWrap: false,
                                style: nameStyle,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildMiniFollowButton(user, compact: compact),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '@${user.username} • ${user.sport}',
                style: TextStyle(
                  color: FeedPalette.muted,
                  fontSize: compact ? 11 : (nameSize < 16 ? 12 : 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRichUserCard(UserProfile user) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfilePage(user: user)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: FeedPalette.panelDecoration(radius: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRichUserCardHeader(user),
            if (user.bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                user.bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: FeedPalette.text,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Publicaciones populares (Mini grid simulado)
            SizedBox(
              height: 100,
              child: Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      decoration: BoxDecoration(
                        color: FeedPalette.background,
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: NetworkImage(
                            'https://images.unsplash.com/photo-${1517800000000 + (user.username.hashCode) + i}?w=200&q=80',
                          ),
                          fit: BoxFit.cover,
                          onError: (err, st) {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniFollowButton(UserProfile user, {bool compact = false}) {
    return ListenableBuilder(
      listenable: _socialState,
      builder: (context, child) {
        final isFollowing = _socialState.isFollowing(user.username);
        if (user.username == _socialState.currentUser.username) {
          return const SizedBox.shrink();
        }

        return ElevatedButton(
          onPressed: () => _toggleFollow(user, isFollowing),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isFollowing ? FeedPalette.surfaceSoft : FeedPalette.accent,
            foregroundColor: isFollowing ? FeedPalette.text : Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 6 : 8,
            ),
            minimumSize: Size(compact ? 76 : 90, compact ? 32 : 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isFollowing
                  ? BorderSide(color: FeedPalette.border)
                  : BorderSide.none,
            ),
          ),
          child: Text(
            isFollowing ? 'Siguiendo' : 'Seguir',
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: isFollowing ? FeedPalette.text : Colors.white,
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleFollow(UserProfile user, bool isFollowing) async {
    try {
      if (isFollowing) {
        await _socialService.unfollowUser(user.username);
        _socialState.updateFollowStatus(user.username, false);
      } else {
        await _socialService.followUser(user.username);
        _socialState.updateFollowStatus(user.username, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cambiar seguimiento')),
        );
      }
    }
  }

  void _showRoutineDetails(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: _socialState,
        builder: (context, _) {
          final isSaved = r['isSaved'] ?? false;
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                _buildHeroImage(r['image'], r['title']),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        r['title'],
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: FeedPalette.text),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Por ${r['author']}',
                        style: TextStyle(
                            color: FeedPalette.accent,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        r['description'] ?? 'Sin descripción disponible.',
                        style:
                            TextStyle(color: FeedPalette.muted, fontSize: 16),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'EJERCICIOS',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: FeedPalette.text,
                            letterSpacing: 1),
                      ),
                      const SizedBox(height: 16),
                      if (r['exercises'] != null)
                        ...(r['exercises'] as List)
                            .map((e) => _buildExerciseRow(e)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaved
                          ? null
                          : () {
                              _socialState.saveRoutine(r['id']);
                              Navigator.pop(ctx);
                            },
                      style: FeedPalette.primaryButtonStyle(radius: 16),
                      child: Text(isSaved ? 'Guardada' : 'Guardar Rutina'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showGroupDetails(Map<String, dynamic> g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: _socialState,
        builder: (context, _) {
          final isJoined = g['isJoined'] ?? false;
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                _buildHeroImage(g['image'], g['name']),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g['name'],
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: FeedPalette.text),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: FeedPalette.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              g['category'],
                              style: TextStyle(
                                  color: FeedPalette.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.people_alt_rounded,
                              color: FeedPalette.muted, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${g['members']} miembros activos',
                            style: TextStyle(
                                color: FeedPalette.muted,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        g['description'] ?? 'Sin descripción disponible.',
                        style:
                            TextStyle(color: FeedPalette.muted, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isJoined
                          ? null
                          : () {
                              _socialState.joinGroup(g['id']);
                              Navigator.pop(ctx);
                            },
                      style: FeedPalette.primaryButtonStyle(radius: 16),
                      child: Text(isJoined ? 'Miembro' : 'Unirse al Grupo'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroImage(String url, String tag) {
    return Stack(
      children: [
        Hero(
          tag: tag,
          child: Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              image: DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.3),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
              ],
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: CircleAvatar(
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseRow(Map<String, dynamic> e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FeedPalette.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FeedPalette.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FeedPalette.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.fitness_center, color: FeedPalette.accent, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              e['name'],
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: FeedPalette.text,
                  fontSize: 15),
            ),
          ),
          Text(
            e['sets'],
            style: TextStyle(
                color: FeedPalette.accent,
                fontWeight: FontWeight.w900,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}
