import 'package:flutter/material.dart';
import 'post_model.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import '../../shared/widgets/common/smart_image.dart';
import 'duel_service.dart';
import 'social_service.dart';
import 'social_state.dart';
import 'package:rms/core/utils/profile_avatar.dart';

class DuelosView extends StatefulWidget {
  const DuelosView({super.key});

  @override
  State<DuelosView> createState() => _DuelosViewState();
}

class _DuelosViewState extends State<DuelosView>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late AnimationController _pulseController;
  bool _isGeneratingDuel = false;
  bool _isLoadingDuels = true;

  final DuelService _duelService = DuelService();
  final SocialService _socialService = SocialService();
  final SocialState _socialState = SocialState();

  List<Map<String, dynamic>> _invitaciones = [];
  List<Map<String, dynamic>> _duelosActivos = [];
  Map<String, dynamic> _stats = {
    'wins': 0,
    'points': 0,
    'activeCount': 0,
    'rankPosition': 0,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadDuels();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDuels();
    }
  }

  Future<String?> _fetchAvatarForUsername(
    String username,
    String fallbackName,
  ) async {
    try {
      final profile = await _socialService.getProfile(username);
      return ProfileAvatar.forPath(
        profile['imagePath'] ?? profile['userImage'],
        profile['name']?.toString() ??
            profile['username']?.toString() ??
            fallbackName,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _hydrateDuelAvatar(
    Map<String, dynamic> duel,
  ) async {
    final copy = Map<String, dynamic>.from(duel);

    if (copy['isMulti'] == true) {
      final participants = List<String>.from(copy['participants'] ?? []);
      final images = (copy['participantImages'] as List?) ?? [];
      final opponentUsernames =
          List<String>.from(copy['opponentUsernames'] ?? []);
      final newImages = <String>[];

      for (var i = 0; i < participants.length; i++) {
        final name = participants[i];
        final raw = i < images.length ? images[i]?.toString() : null;
        if (i == 0 || name == 'Tú') {
          newImages.add(ProfileAvatar.forCurrentUser());
          continue;
        }

        var resolved = ProfileAvatar.forPath(raw, name);
        final usernameIndex = i - 1;
        if (usernameIndex >= 0 && usernameIndex < opponentUsernames.length) {
          final username = opponentUsernames[usernameIndex].trim();
          if (username.isNotEmpty) {
            resolved =
                await _fetchAvatarForUsername(username, name) ?? resolved;
          }
        }
        newImages.add(resolved);
      }

      copy['participantImages'] = newImages;
      return copy;
    }

    final name = copy['name']?.toString() ?? 'Amigo';
    var resolved = ProfileAvatar.forPath(copy['opponentImage'], name);
    final username = copy['opponentUsername']?.toString().trim() ?? '';
    if (username.isNotEmpty) {
      resolved = await _fetchAvatarForUsername(username, name) ?? resolved;
    }
    copy['opponentImage'] = resolved;
    return copy;
  }

  Future<List<Map<String, dynamic>>> _hydrateDuelAvatars(
    List<Map<String, dynamic>> duels,
  ) async {
    final hydrated = <Map<String, dynamic>>[];
    for (final duel in duels) {
      hydrated.add(await _hydrateDuelAvatar(duel));
    }
    return hydrated;
  }

  Future<void> _persistHydratedDuels(
    Map<String, dynamic> state,
    List<Map<String, dynamic>> hydratedDuels,
  ) async {
    final active = List<Map<String, dynamic>>.from(
      (state['activeDuels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final byId = {
      for (final duel in hydratedDuels)
        if (duel['id'] != null) duel['id'].toString(): duel,
    };

    var changed = false;
    for (var i = 0; i < active.length; i++) {
      final id = active[i]['id']?.toString();
      final updated = id != null ? byId[id] : null;
      if (updated == null) continue;
      active[i] = updated;
      changed = true;
    }

    if (!changed) return;
    final nextState = Map<String, dynamic>.from(state);
    nextState['activeDuels'] = active;
    await _duelService.saveState(nextState);
  }

  Future<void> _loadDuels() async {
    setState(() => _isLoadingDuels = true);
    final state = await _duelService.loadState();
    final dailyStats = await _duelService.applyDailyTrainingPointsOnce();
    final refreshed = await _duelService.loadState();
    final rawDuels = List<Map<String, dynamic>>.from(
      refreshed['activeDuels'] as List? ?? [],
    );
    final onlyActiveDuels =
        rawDuels.where((d) => d['status']?.toString() == 'active').toList();
    final seen = <String>{};
    final dedupedDuels = <Map<String, dynamic>>[];
    for (final duel in onlyActiveDuels) {
      final id = duel['id']?.toString() ?? '';
      final opp = duel['opponentUsername']?.toString() ??
          duel['name']?.toString() ??
          '';
      final key = '${duel['isMulti'] == true ? 'm' : 's'}|$id|$opp';
      if (seen.contains(key)) continue;
      seen.add(key);
      dedupedDuels.add(duel);
    }
    final hydratedDuels = await _hydrateDuelAvatars(dedupedDuels);
    if (hydratedDuels.isNotEmpty) {
      await _persistHydratedDuels(refreshed, hydratedDuels);
    }

    if (mounted) {
      setState(() {
        _invitaciones = List<Map<String, dynamic>>.from(
          refreshed['invitations'] as List? ?? [],
        );
        _duelosActivos = hydratedDuels;
        _stats = Map<String, dynamic>.from(
          refreshed['stats'] as Map? ?? state['stats'] as Map? ?? _stats,
        );
        // Mostrar puntos diarios reales (máximo 100) en cabecera.
        _stats['points'] =
            (dailyStats['points'] as int?) ?? (_stats['points'] ?? 0);
        _isLoadingDuels = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteDuel(int duelId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar duelo'),
        content: Text(
          '¿Quieres abandonar el duelo con $label? Se borrará de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final deleted = await _duelService.deleteDuel(duelId);
    if (!mounted) return;

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar el duelo. Inténtalo de nuevo.'),
        ),
      );
      return;
    }

    await _loadDuels();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Duelo eliminado')),
    );
  }

  void _createNewDuel() async {
    final username = _socialState.currentUser.username;
    final followingRaw = await _socialService.getFollowing(username);
    final List<UserProfile> allFriends = followingRaw
        .map((u) {
          return UserProfile(
            id: u['id'] is int ? u['id'] : int.tryParse('${u['id']}'),
            username: u['username']?.toString() ?? '',
            displayName:
                u['name']?.toString() ?? u['username']?.toString() ?? '',
            userImage: ProfileAvatar.forPath(
              u['avatar'] ?? u['userImage'],
              u['name']?.toString() ?? u['username']?.toString() ?? 'U',
            ),
            bio: u['bio']?.toString() ?? '',
            sport: u['sport']?.toString() ?? 'Fitness',
          );
        })
        .where((u) => u.username.isNotEmpty)
        .toList();

    if (!mounted) return;

    if (allFriends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sigue a alguien para retarlo. Tus duelos se guardarán en tu cuenta.',
          ),
        ),
      );
      return;
    }

    List<UserProfile> filteredFriends = List.from(allFriends);
    final List<UserProfile> selectedFriends = [];
    String searchQuery = '';

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Crear Nuevo Duelo'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  style: FeedPalette.bodyTextStyle,
                  decoration: FeedPalette.textFieldDecoration(
                    hint: 'Buscar amigos...',
                    prefixIcon: Icon(Icons.search, color: FeedPalette.muted),
                    radius: 15,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      searchQuery = value.toLowerCase();
                      filteredFriends = allFriends.where((u) {
                        return u.displayName.toLowerCase().contains(
                                  searchQuery,
                                ) ||
                            u.username.toLowerCase().contains(searchQuery);
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.4,
                  ),
                  child: filteredFriends.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No se encontraron amigos'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredFriends.length,
                          itemBuilder: (context, index) {
                            final user = filteredFriends[index];
                            final isSelected = selectedFriends.any(
                              (u) => u.username == user.username,
                            );
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: FeedPalette.surfaceSoft,
                                child: ClipOval(
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: SmartImage(
                                      imageUrl: user.userImage,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '@${user.username}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.green
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.green
                                        : FeedPalette.border,
                                    width: 2,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 18,
                                          color: Colors.white,
                                        )
                                      : const Icon(
                                          Icons.add,
                                          size: 18,
                                          color: Colors.transparent,
                                        ),
                                ),
                              ),
                              onTap: () {
                                setDialogState(() {
                                  if (isSelected) {
                                    selectedFriends.removeWhere(
                                      (u) => u.username == user.username,
                                    );
                                  } else {
                                    selectedFriends.add(user);
                                  }
                                });
                              },
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
              child: Text(
                'CANCELAR',
                style: TextStyle(color: FeedPalette.muted),
              ),
            ),
            ElevatedButton(
              onPressed: selectedFriends.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A11CB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'CREAR',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (result == true && selectedFriends.isNotEmpty) {
      setState(() => _isGeneratingDuel = true);
      final opponents = selectedFriends
          .map(
            (u) => {
              'username': u.username,
              'displayName': u.displayName,
              'userImage': u.userImage,
            },
          )
          .toList();
      final created = await _duelService.createDuel(
        opponents: opponents,
        isMulti: selectedFriends.length > 1,
      );
      if (!created) {
        if (mounted) {
          setState(() => _isGeneratingDuel = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo crear el duelo.')),
          );
        }
        return;
      }
      await _loadDuels();
      if (mounted) {
        setState(() => _isGeneratingDuel = false);
        _showDuelCreatedSuccess(
          selectedFriends.map((u) => u.displayName).join(', '),
        );
      }
    }
  }

  void _showDuelCreatedSuccess(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('¡Duelo contra $name creado con éxito!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _aceptarInvitacion(int id) async {
    final inv = _invitaciones.firstWhere((element) => element['id'] == id);
    await _duelService.acceptInvitation(id);
    await _loadDuels();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Has aceptado el reto de ${inv['name']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoadingDuels) {
      return Scaffold(
        backgroundColor: FeedPalette.background,
        body: Center(
          child: CircularProgressIndicator(color: FeedPalette.accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FeedPalette.background,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              if (_invitaciones.isNotEmpty) ...[
                _buildChallengeInvitations(),
                const SizedBox(height: 24),
              ],
              _buildActiveDuelsSection(),
              const SizedBox(height: 32),
              _buildLeaderboardPreview(),
              const SizedBox(height: 140),
            ],
          ),
          if (_isGeneratingDuel) _buildGeneratingOverlay(),
        ],
      ),
    );
  }

  Widget _buildGeneratingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.2),
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.bolt,
                      color: Colors.amber,
                      size: 80,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'BUSCANDO OPONENTES...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Analizando rendimiento de tus amigos',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  String _duelRankLabel() {
    final rank = _stats['rankPosition'];
    if (rank != null) return '$rank';
    final points = (_stats['points'] as num?)?.toInt() ?? 0;
    return points > 0 ? '2' : '-';
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Arena de Duelos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Tu posición: #${_duelRankLabel()} en el ranking',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.amber,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildHeaderStat(
                '${_duelosActivos.where((d) => d['status'] == 'active').length}',
                'ACTIVOS',
              ),
              const SizedBox(width: 32),
              _buildHeaderStat('${_stats['wins'] ?? 0}', 'VICTORIAS'),
              const SizedBox(width: 32),
              _buildHeaderStat('${_stats['points'] ?? 0}', 'PUNTOS'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeInvitations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Retos Disponibles',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: FeedPalette.text,
          ),
        ),
        const SizedBox(height: 12),
        ..._invitaciones.map(
          (inv) => _buildInvitationItem(
            inv['id'],
            inv['name'],
            inv['challenge'],
            inv['expires'],
          ),
        ),
      ],
    );
  }

  Widget _buildInvitationItem(
    int id,
    String name,
    String challenge,
    String expires,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FeedPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: FeedPalette.accent,
            child: const Icon(Icons.bolt, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: FeedPalette.text,
                  ),
                ),
                Text(
                  challenge,
                  style: TextStyle(fontSize: 12, color: FeedPalette.muted),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _aceptarInvitacion(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: FeedPalette.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDuelsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duelos en Curso',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: FeedPalette.text,
          ),
        ),
        const SizedBox(height: 16),
        if (_duelosActivos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: FeedPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: FeedPalette.border),
            ),
            child: Text(
              'Aún no tienes duelos. Pulsa + para retar a alguien que sigues.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FeedPalette.muted),
            ),
          )
        else
          ..._duelosActivos.map((duel) {
            if (duel['isMulti'] == true) {
              final images = duel['participantImages'] as List?;
              return _buildMultiDuelCard(
                title: duel['title']?.toString() ?? 'Duelo grupal',
                participants: List<String>.from(duel['participants'] ?? []),
                participantImages: images?.map((e) => e?.toString()).toList(),
                scores: (duel['scores'] as List?)
                        ?.map((e) => int.tryParse('$e') ?? 0)
                        .toList() ??
                    [],
                winningIndex: duel['winningIndex'] as int? ?? 0,
                progress: (duel['progress'] as num?)?.toDouble() ?? 0.1,
                status: duel['status']?.toString() ?? 'active',
                duelId: int.tryParse('${duel['id']}'),
              );
            }
            return Column(
              children: [
                _buildDuelCard(
                  duel['name']?.toString() ?? 'Amigo',
                  int.tryParse('${duel['myScore']}') ?? 0,
                  int.tryParse('${duel['opponentScore']}') ?? 0,
                  duel['winning'] == true,
                  duel['status']?.toString() ?? 'active',
                  opponentImage: duel['opponentImage']?.toString(),
                  duelId: duel['id'] as int?,
                ),
                const SizedBox(height: 16),
              ],
            );
          }),
      ],
    );
  }

  Widget _buildMultiDuelCard({
    required String title,
    required List<String> participants,
    List<String?>? participantImages,
    required List<int> scores,
    required int winningIndex,
    required double progress,
    required String status,
    int? duelId,
  }) {
    final bool isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: [Color(0xFF2575FC), Color(0xFF6A11CB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white70 : FeedPalette.muted,
                  ),
                ),
              ),
              if (duelId != null)
                IconButton(
                  onPressed: () => _confirmDeleteDuel(duelId, title),
                  icon: Icon(
                    Icons.delete_outline,
                    color: isActive ? Colors.white70 : FeedPalette.muted,
                    size: 22,
                  ),
                  tooltip: 'Abandonar duelo',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(participants.length, (i) {
              bool isWinner = i == winningIndex;
              return Column(
                children: [
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: isWinner
                            ? Colors.amber.withValues(alpha: 0.2)
                            : (isActive ? Colors.white10 : FeedPalette.surface),
                        child: ClipOval(
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: _duelAvatar(
                              i == 0
                                  ? _socialState.currentUser.userImage
                                  : (participantImages != null &&
                                          i < participantImages.length
                                      ? participantImages[i]
                                      : null),
                              participants[i],
                            ),
                          ),
                        ),
                      ),
                      if (isWinner)
                        const Icon(
                          Icons.workspace_premium,
                          color: Colors.amber,
                          size: 20,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    participants[i],
                    style: TextStyle(
                      fontWeight:
                          isWinner ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                      color: isActive ? Colors.white : FeedPalette.text,
                    ),
                  ),
                  Text(
                    '${scores[i]} pt',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? Colors.white70 : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: isActive
                      ? Colors.white.withValues(alpha: 0.1)
                      : FeedPalette.surface,
                  color: isActive ? Colors.white : FeedPalette.accent,
                  minHeight: 8,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _duelAvatar(String? imageUrl, String name) {
    final resolved = ProfileAvatar.forPath(imageUrl, name);
    return SmartImage(
      imageUrl: resolved,
      fit: BoxFit.cover,
      placeholder: Icon(Icons.person, color: FeedPalette.muted),
      errorWidget: Icon(Icons.person, color: FeedPalette.muted),
    );
  }

  Widget _buildDuelCard(
    String name,
    int myScore,
    int opponentScore,
    bool winning,
    String status, {
    String? opponentImage,
    int? duelId,
  }) {
    final isPending = status == 'pending';
    final isActive = status == 'active';
    double progress = (myScore + opponentScore) == 0
        ? 0.5
        : myScore / (myScore + opponentScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Opacity(
        opacity: isPending ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFF2575FC), Color(0xFF6A11CB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : FeedPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isPending
                  ? Colors.amber.withValues(alpha: 0.3)
                  : (isActive
                      ? Colors.transparent
                      : (winning
                          ? Colors.green.withValues(alpha: 0.2)
                          : FeedPalette.surface)),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isPending
                          ? 'PENDIENTE'
                          : (winning ? '¡VAS GANANDO!' : '¡MÁS ESFUERZO!'),
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : (isPending
                                ? Colors.amber
                                : (winning ? Colors.green : Colors.red)),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (duelId != null)
                    IconButton(
                      onPressed: () => _confirmDeleteDuel(duelId, name),
                      icon: Icon(
                        Icons.delete_outline,
                        color: isActive ? Colors.white70 : FeedPalette.muted,
                        size: 22,
                      ),
                      tooltip: 'Abandonar duelo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    isPending ? 'Esperando confirmación' : 'Expira en 4h',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? Colors.white70 : FeedPalette.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _simpleAvatar(
                    'Tú',
                    myScore,
                    true,
                    isActive,
                    imageUrl: _socialState.currentUser.userImage,
                  ),
                  Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isActive
                          ? Colors.white24
                          : FeedPalette.muted.withValues(alpha: 0.35),
                    ),
                  ),
                  _simpleAvatar(
                    name,
                    opponentScore,
                    false,
                    isActive,
                    imageUrl: opponentImage,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 12,
                      backgroundColor: isActive
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.red.withValues(alpha: 0.1),
                      color: isActive ? Colors.white : Colors.blue,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _simpleAvatar(
    String name,
    int score,
    bool isMe,
    bool isActive, {
    String? imageUrl,
  }) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isActive ? Colors.white24 : FeedPalette.surface,
          child: ClipOval(
            child: SizedBox(
              width: 48,
              height: 48,
              child: _duelAvatar(imageUrl, name),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isActive ? Colors.white : FeedPalette.text,
          ),
        ),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: score),
          duration: const Duration(seconds: 1),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Text(
              '$value',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : FeedPalette.accent,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLeaderboardPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ranking de Amigos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: FeedPalette.text,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: FeedPalette.surfaceSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: FeedPalette.border),
          ),
          child: Column(
            children: [
              _buildLeaderTile(1, 'Mario Fitness', 1250, true),
              _buildLeaderTile(2, 'Tú (Jorge)', 850, false),
              _buildLeaderTile(3, 'Elena Yoga', 720, false),
              _buildLeaderTile(4, 'Sergio Gil', 600, false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: FeedPalette.accent.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: FeedPalette.accent,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _createNewDuel,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'NUEVO DUELO',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderTile(int pos, String name, int score, bool top) {
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: top ? Colors.amber : FeedPalette.surface,
        child: Text(
          '$pos',
          style: TextStyle(
            color: top ? FeedPalette.background : FeedPalette.text,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: FeedPalette.text,
        ),
      ),
      trailing: Text(
        '$score XP',
        style: TextStyle(
          color: FeedPalette.accent,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
