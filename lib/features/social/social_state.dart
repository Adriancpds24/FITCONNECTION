import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rms/core/utils/profile_avatar.dart';
import 'post_model.dart';
import 'social_service.dart';
import 'duel_service.dart';
import '../auth/auth_service.dart';

class SocialState extends ChangeNotifier {
  // Use a singleton pattern for easy access throughout the app
  static final SocialState _instance = SocialState._internal();
  factory SocialState() => _instance;
  SocialState._internal() {
    _initMockData();
    _loadHighlights(); // Load saved highlights
    _loadViewedStories(); // Load viewed stories
    _loadChallengesPersistence(); // Load joined challenges
    if (AuthService().isAuthenticated && AuthService().username != null) {
      syncCurrentUser().then((_) {
        final username = AuthService().username;
        if (username != null && AuthService().isAuthenticated) {
          syncFollowing(username);
        }
      });
    }
  }

  static const String _highlightsKeyPrefix = 'user_highlights_';
  static const String _viewedStoriesKeyPrefix = 'viewed_stories_';

  final List<Post> _posts = [];
  final List<Highlight> _currentHighlights = [];
  final Map<String, List<Highlight>> _userHighlightsCache = {};
  List<Map<String, String>> _stories = [];
  final Set<String> _followedUsernames = {};
  late UserProfile _currentUser;
  bool _isSynced = false;
  List<Map<String, dynamic>> _storyHistory = [];
  bool _isLoading = false;
  List<Map<String, dynamic>> _notifications = [];
  // Store notifications for all users in this session to simulate "real-time"
  static final Map<String, List<Map<String, dynamic>>> _sessionNotifications =
      {};
  final DateTime _startTime = DateTime.now();
  final Set<String> _viewedStoryIds = <String>{};
  final List<Map<String, dynamic>> _followRequests = [];
  int _duelPoints = 0;
  bool _duelCompletedToday = false;
  final List<Map<String, dynamic>> _challenges = [
    {
      'id': 'c1',
      'title': '30 Días de Plancha',
      'participants': 1240,
      'isJoined': false,
      'description':
          'OBJETIVO: Fortalecer el core y mejorar la postura.\n\nCÓMO FUNCIONA:\nCada día deberás realizar una serie de planchas isométricas. Empezaremos con 20 segundos el Día 1, aumentando 10 segundos cada 2 días.\n\nREQUISITOS:\n- Espacio libre de 2 metros.\n- Cronómetro.\n- ¡Cero excusas!',
      'image':
          'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&q=80',
      'requirements': 'Sin equipamiento',
      'difficulty': 'Media',
    },
    {
      'id': 'c2',
      'title': 'Maratón de Sentadillas',
      'participants': 850,
      'isJoined': false,
      'description':
          'OBJETIVO: Hipertrofia de piernas y resistencia muscular.\n\nCÓMO FUNCIONA:\nEl reto consiste en acumular 2500 sentadillas en 30 días. Empezarás con 50 diarias y terminarás con 150 el último día.\n\nTÉCNICA:\nMantén la espalda recta y baja hasta que tus muslos estén paralelos al suelo.',
      'image':
          'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80',
      'requirements': 'Peso corporal',
      'difficulty': 'Alta',
    },
    {
      'id': 'c3',
      'title': '10k Pasos Diarios',
      'participants': 3100,
      'isJoined': false,
      'description':
          'OBJETIVO: Mejorar la salud cardiovascular y quemar calorías.\n\nCÓMO FUNCIONA:\nSincroniza tu podómetro y asegúrate de llegar a los 10,000 pasos antes de dormir.\n\nPREMIO:\nAl completar los 30 días recibirás la insignia "Caminante de Élite" y 500 FitCoins.',
      'image':
          'https://images.unsplash.com/photo-1483721310020-03333e577078?w=800&q=80',
      'requirements': 'Calzado cómodo',
      'difficulty': 'Baja',
    },
    {
      'id': 'c4',
      'title': 'CrossFit Power',
      'participants': 520,
      'isJoined': false,
      'description':
          'OBJETIVO: Potencia explosiva y acondicionamiento total.\n\nCÓMO FUNCIONA:\n3 WODs semanales de alta intensidad. Cada lunes recibirás el entrenamiento en tu sección de rutinas.\n\nATENCIÓN:\nEste reto es nivel EXPERTO. Asegúrate de calentar correctamente.',
      'image':
          'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=800&q=80',
      'requirements': 'Barra y Pesas',
      'difficulty': 'Experto',
    },
  ];

  final List<Map<String, dynamic>> _routines = [
    {
      'id': 'r1',
      'title': 'Full Body Explosivo',
      'difficulty': 'Media',
      'time': '45 min',
      'image':
          'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=500&q=80',
      'author': 'Sergio Trainer',
      'description':
          'Una rutina completa diseñada para quemar grasa y tonificar todo el cuerpo en tiempo récord. Combina ejercicios multiarticulares con intervalos de alta intensidad.',
      'exercises': [
        {'name': 'Burpees', 'sets': '3 x 15'},
        {'name': 'Sentadillas con Salto', 'sets': '4 x 12'},
        {'name': 'Flexiones de Brazos', 'sets': '3 x fallo'},
        {'name': 'Zancadas Alternas', 'sets': '3 x 20'},
        {'name': 'Plancha Abdominal', 'sets': '3 x 45s'},
      ],
      'isSaved': false,
    },
    {
      'id': 'r2',
      'title': 'Core de Acero',
      'difficulty': 'Baja',
      'time': '20 min',
      'image':
          'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=500&q=80',
      'author': 'Elena Yoga',
      'description':
          'Enfócate en fortalecer tu centro. Esta rutina de bajo impacto pero alta intensidad es ideal para mejorar la postura y definir el abdomen.',
      'exercises': [
        {'name': 'Crunch Abdominal', 'sets': '3 x 25'},
        {'name': 'Mountain Climbers', 'sets': '3 x 40'},
        {'name': 'Elevación de Piernas', 'sets': '3 x 15'},
        {'name': 'Plancha Lateral', 'sets': '2 x 30s c/u'},
      ],
      'isSaved': false,
    },
    {
      'id': 'r3',
      'title': 'Piernas de Titán',
      'difficulty': 'Alta',
      'time': '60 min',
      'image':
          'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=500&q=80',
      'author': 'Mario Fitness',
      'description':
          'Prepárate para el reto definitivo de tren inferior. Enfocada en fuerza bruta e hipertrofia para cuádriceps, isquios y glúteos.',
      'exercises': [
        {'name': 'Sentadilla con Barra', 'sets': '4 x 10'},
        {'name': 'Prensa de Piernas', 'sets': '3 x 12'},
        {'name': 'Peso Muerto Rumano', 'sets': '3 x 12'},
        {'name': 'Extensiones de Cuádriceps', 'sets': '4 x 15'},
        {'name': 'Elevación de Talones', 'sets': '4 x 20'},
      ],
      'isSaved': false,
    },
  ];

  final List<Map<String, dynamic>> _groups = [
    {
      'id': 'g1',
      'name': 'Calistenia Madrid',
      'members': 450,
      'category': 'Fuerza',
      'image':
          'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=500&q=80',
      'description':
          'Comunidad de entrenamiento con peso corporal en los parques de Madrid. ¡Todos los niveles son bienvenidos!',
      'isJoined': false,
    },
    {
      'id': 'g2',
      'name': 'Runners Retiro',
      'members': 1200,
      'category': 'Running',
      'image':
          'https://images.unsplash.com/photo-1483721310020-03333e577078?w=500&q=80',
      'description':
          'Quedadas diarias para correr en el Parque del Retiro. Grupos por ritmo y distancia.',
      'isJoined': false,
    },
    {
      'id': 'g3',
      'name': 'Yoga & Wellness',
      'members': 800,
      'category': 'Salud',
      'image':
          'https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=500&q=80',
      'description':
          'Un espacio para la meditación, el yoga y el bienestar integral. Sesiones grupales y talleres.',
      'isJoined': false,
    },
  ];

  final List<String> _availableSports = [
    'Gimnasio',
    'Running',
    'Ciclismo',
    'Natación',
    'CrossFit',
    'Yoga',
    'Pilates',
    'Boxeo',
    'Tenis',
    'Pádel',
    'Fútbol',
    'Baloncesto',
    'Senderismo',
    'Escalada',
    'Artes Marciales',
    'Zumba',
  ];

  List<Post> get posts => List.unmodifiable(_posts);
  bool get isLoading => _isLoading;
  List<Map<String, String>> get stories => _stories;
  // This will return the flat list of all slides for the viewer
  List<Map<String, String>> get allStorySlides => _allStorySlides;
  Set<String> get followedUsernames => _followedUsernames;
  UserProfile get currentUser => _currentUser;
  bool get isSynced => _isSynced;
  List<Map<String, dynamic>> get storyHistory => _storyHistory;
  List<Map<String, dynamic>> get notifications => _notifications;
  List<Map<String, dynamic>> get followRequests => _followRequests;
  List<String> get availableSports => List.unmodifiable(_availableSports);
  int get duelPoints => _duelPoints;
  bool get duelCompletedToday => _duelCompletedToday;
  List<Map<String, dynamic>> get challenges => _challenges;
  List<Map<String, dynamic>> get routines => _routines;
  List<Map<String, dynamic>> get groups => _groups;

  Duration get appUsageDuration => DateTime.now().difference(_startTime);

  List<Map<String, String>> _allStorySlides = [];
  Set<String> get viewedStoryIds => _viewedStoryIds;

  Post? getPost(String id) {
    try {
      return _posts.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> syncPost(String id) async {
    try {
      final post = await SocialService().getPostById(id);
      final index = _posts.indexWhere((p) => p.id == id);
      if (index != -1) {
        _posts[index] = post;
      } else {
        _posts.add(post);
      }
      notifyListeners();
      // Importante: el endpoint de post no siempre incluye comentarios.
      // Los cargamos aparte para que en "Publicación" (por ejemplo al compartir)
      // se vean likes/comentarios reales.
      await _fetchCommentsForPost(id);
    } catch (e) {
      if ('$e'.contains('404')) {
        _posts.removeWhere((p) => p.id == id);
        notifyListeners();
        return;
      }
      debugPrint('Error syncing post $id: $e');
    }
  }

  bool isStoryViewed(String storyId, {bool isOwn = false}) {
    return _viewedStoryIds.contains(storyId);
  }

  void markStoryAsViewed(String storyId, {bool isOwn = false}) {
    if (_viewedStoryIds.contains(storyId)) return;
    _viewedStoryIds.add(storyId);
    _saveViewedStories();
    notifyListeners();
  }

  void setCurrentUser(UserProfile profile) {
    _currentUser = profile;
    _loadHighlights();
    _loadViewedStories();
    _loadChallengesPersistence();
    if (AuthService().isAuthenticated && profile.username.trim().isNotEmpty) {
      syncHighlights(profile.username);
      syncFollowing(profile.username);
    }
    notifyListeners();
  }

  void onLogout() {
    _posts.clear();
    _stories.clear();
    _currentHighlights.clear(); // Clear highlights strictly
    _followedUsernames.clear();
    _allStorySlides.clear();
    _viewedStoryIds.clear();
    _notifications.clear();
    _sessionNotifications.clear();
    _isSynced = false;
    _initMockData();
    notifyListeners();
  }

  void _initMockData() {
    _notifications.clear();
    _sessionNotifications.clear();
    _posts.clear();
    _stories.clear();
    _followedUsernames.clear();
    _allStorySlides.clear();
    _currentHighlights.clear();

    _currentUser = UserProfile(
      username: '',
      displayName: '',
      userImage: '',
      bio: '',
      sport: '',
      followers: 0,
      following: 0,
      posts: 0,
    );
  }

  List<Highlight> getHighlightsForUser(String username) {
    if (username == _currentUser.username) {
      return _currentHighlights;
    }

    return _userHighlightsCache[username] ?? [];
  }

  List<String> getUniquePostsForUser(String username) {
    return _posts
        .where((post) =>
            post.username == username && post.postImage.trim().isNotEmpty)
        .map((post) => post.postImage)
        .toSet()
        .toList(growable: false);
  }

  final Set<String> _followRequestedUsernames = {};

  bool isFollowRequested(String username) =>
      _followRequestedUsernames.contains(username);

  void setFollowRequested(String username, bool requested) {
    if (requested) {
      _followRequestedUsernames.add(username);
    } else {
      _followRequestedUsernames.remove(username);
    }
    notifyListeners();
  }

  void updateFollowStatus(String username, bool isFollowing) {
    if (isFollowing) {
      if (!_followedUsernames.contains(username)) {
        _followedUsernames.add(username);
        _currentUser.following++;
      }
    } else {
      if (_followedUsernames.contains(username)) {
        _followedUsernames.remove(username);
        _currentUser.following--;
      }
    }
    notifyListeners();
  }

  Future<void> syncFollowing(String username) async {
    if (_isSynced || AuthService().token == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      final following = await SocialService().getFollowing(username);
      _followedUsernames.clear();
      for (var user in following) {
        if (user['username'] != null) {
          _followedUsernames.add(user['username']);
        }
      }
      // Only sync numerical count if we are syncing the current user
      if (username == _currentUser.username) {
        _currentUser.following = _followedUsernames.length;
      }

      // Also fetch notifications
      await syncNotifications();

      _isSynced = true;
      // We don't notify here because syncStories/syncPosts will do it
      await syncStories();
      await syncPosts();
      await syncSavedPosts();
      await updateDailyDuelPoints();
    } catch (e) {
      _isSynced = false;
      debugPrint('Error syncing following: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncStories() async {
    if (AuthService().token == null) return;
    try {
      final storiesData = await SocialService().getActiveStories();

      // Flat list of all slides for the viewer
      _allStorySlides = storiesData.map<Map<String, String>>((s) {
        final isOwn = s['username'] == _currentUser.username;
        final userImage = (s['userImage'] ?? s['imagePath'] ?? '').toString();
        return {
          'id': s['id']?.toString() ?? '',
          'username': s['username']?.toString() ?? 'Usuario',
          'image': s['image']?.toString() ?? '',
          'userImage': userImage,
          'isOwn': isOwn.toString(),
        };
      }).toList();

      // Filter and group to show only ONE bubble per user in the bar
      final Map<String, Map<String, String>> uniqueUsers = {};

      // Ensure current user is always first as a placeholder if they have no stories
      uniqueUsers[_currentUser.username] = {
        'username': _currentUser.username,
        'image': '', // Empty image means it's a "Add story" placeholder
        'userImage': _currentUser.userImage,
        'isOwn': 'true',
        'flatIndex': '-1',
      };

      for (int i = 0; i < _allStorySlides.length; i++) {
        final story = _allStorySlides[i];
        final uname = story['username']!;

        // If it's the first story we see for this user, use it for the bubble
        if (!uniqueUsers.containsKey(uname) ||
            uniqueUsers[uname]!['image'] == '') {
          final bubble = Map<String, String>.from(story);
          bubble['flatIndex'] = i.toString();
          uniqueUsers[uname] = bubble;
        }
      }

      // Convert map to list, current user first
      final List<Map<String, String>> groupedStories = [];
      groupedStories.add(uniqueUsers[_currentUser.username]!);

      uniqueUsers.forEach((key, value) {
        if (key != _currentUser.username) {
          groupedStories.add(value);
        }
      });

      _stories = groupedStories;

      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing stories: $e');
    }

    // Also sync the profile to get real follower/following counts
    await syncProfile();
  }

  Future<void> syncProfile() async {
    if (!AuthService().isAuthenticated) return;
    if (_currentUser.username.trim().isEmpty) return;
    try {
      final profileData = await SocialService().getProfile(
        _currentUser.username,
      );
      _currentUser = UserProfile.fromJson(profileData);
      await AuthService().syncSessionFromProfile(_currentUser);
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing profile: $e');
    }
  }

  Future<void> syncStoryHistory() async {
    try {
      final history = await SocialService().getStoryHistory();
      // Combine with active stories to allow creating highlights from current stories too
      final active = await SocialService().getActiveStories();
      final ownActive =
          active.where((s) => s['username'] == _currentUser.username).toList();

      _storyHistory = [...ownActive, ...history].map((s) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(s);
        // Ensure a unique string ID for selection logic
        final dynamic originalId = item['id'];
        if (originalId == null) {
          final String fallback = item['imagePath'] ?? item['image'] ?? '';
          item['id'] =
              "sn_${fallback.hashCode}_${DateTime.now().microsecondsSinceEpoch}";
        } else {
          item['id'] = originalId.toString();
        }
        return item;
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing story history: $e');
    }
  }

  Future<void> syncNotifications() async {
    try {
      final data = await SocialService().getNotifications();
      await syncFollowRequests();
      final pendingRequestUsernames = _followRequests
          .map((r) => r['username']?.toString().toLowerCase() ?? '')
          .where((username) => username.isNotEmpty)
          .toSet();

      _notifications = data.map((n) {
        final senderId = n['senderId'];
        int? senderIdInt;
        if (senderId is int) {
          senderIdInt = senderId;
        } else if (senderId is num) {
          senderIdInt = senderId.toInt();
        }
        return {
          'id': n['id'].toString(),
          'username': n['senderUsername'] ?? 'Sistema',
          'type': n['type'],
          'content': n['content'],
          'time': _formatTime(n['createdAt']),
          'image': n['senderImage'] ?? '',
          'read': n['read'] == true,
          'postImage': n['postImage'],
          'postId': n['postId'],
          'senderId': senderIdInt,
        };
      }).where((n) {
        final type = n['type']?.toString().toLowerCase() ?? '';
        if (type != 'follow_request') return true;
        final username = n['username']?.toString().toLowerCase() ?? '';
        return pendingRequestUsernames.contains(username);
      }).toList();

      // Merge with session notifications, but avoid duplicates by ID or content
      final sessionNotifs = _sessionNotifications[_currentUser.username] ?? [];
      final Set<String> existingContents =
          _notifications.map((n) => "${n['username']}_${n['content']}").toSet();

      final List<Map<String, dynamic>> filteredSession =
          sessionNotifs.where((sn) {
        final type = sn['type']?.toString().toLowerCase() ?? '';
        final username = sn['username']?.toString().toLowerCase() ?? '';
        final content = sn['content']?.toString() ?? '';
        if (type == 'follow_request') {
          return pendingRequestUsernames.contains(username);
        }
        if (type == 'system' &&
            content.startsWith('Has aceptado la solicitud de seguimiento')) {
          return false;
        }
        return !existingContents.contains("${sn['username']}_${sn['content']}");
      }).toList();

      _notifications = [...filteredSession, ..._notifications];

      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing notifications: $e');
    }
  }

  Future<void> syncFollowRequests() async {
    try {
      final requests = await SocialService().getFollowRequests();
      _followRequests.clear();
      _followRequests.addAll(requests.map((r) => {
            'id': r['id'],
            'username': r['username'],
            'name': r['name'] ?? r['username'],
            'image': r['userImage'] ?? '',
          }));
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing follow requests: $e');
    }
  }

  String _formatTime(dynamic dateStr) {
    if (dateStr == null) return 'Ahora';
    try {
      final date = DateTime.parse(dateStr.toString());
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
      return 'Hace ${diff.inDays} d';
    } catch (_) {
      return 'Recientemente';
    }
  }

  Future<void> deleteStory(String storyId) async {
    final originalSlides = List<Map<String, String>>.from(_allStorySlides);

    // Optimistic update
    _allStorySlides.removeWhere((s) => s['id'] == storyId);
    notifyListeners();

    try {
      await SocialService().deleteStory(storyId);
      await syncStories();
    } catch (e) {
      // Rollback
      _allStorySlides.clear();
      _allStorySlides.addAll(originalSlides);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addHighlight(String title, List<String> images) async {
    try {
      final cover = images.isNotEmpty
          ? images.first
          : 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=400&q=80';
      await SocialService().createHighlight(title, cover, images);
      await syncHighlights(_currentUser.username);
    } catch (e) {
      debugPrint('Error adding highlight: $e');
      rethrow;
    }
  }

  Future<void> addStoryToHighlight(String highlightId, String imageUrl) async {
    final idx = _currentHighlights.indexWhere((h) => h.id == highlightId);
    if (idx != -1) {
      // Create new list to trigger proper state updates
      final newImages = List<String>.from(_currentHighlights[idx].storyImages)
        ..add(imageUrl);
      final newHighlight = Highlight(
        id: _currentHighlights[idx].id,
        title: _currentHighlights[idx].title,
        coverImage: _currentHighlights[idx].coverImage,
        storyImages: newImages,
      );
      _currentHighlights[idx] = newHighlight;
      await _saveHighlights();
      notifyListeners();
    }
  }

  Future<void> deleteHighlight(Highlight highlight) async {
    try {
      await SocialService().deleteHighlight(highlight.id);
      await syncHighlights(_currentUser.username);
    } catch (e) {
      debugPrint('Error deleting highlight: $e');
      rethrow;
    }
  }

  bool isFollowing(String username) => _followedUsernames.contains(username);

  Future<void> toggleLike(String postId) async {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _posts[index];
      final originalStatus = post.isLiked;

      // Optimistic update
      post.isLiked = !post.isLiked;
      post.likes += post.isLiked ? 1 : -1;
      notifyListeners();

      try {
        await SocialService().toggleLike(postId, originalStatus);
      } catch (e) {
        // Rollback on error
        post.isLiked = originalStatus;
        post.likes += post.isLiked ? 1 : -1;
        notifyListeners();
        rethrow;
      }
    }
  }

  Future<void> toggleBookmark(String postId) async {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final post = _posts[index];
      final originalStatus = post.isBookmarked;

      // Optimistic update
      post.isBookmarked = !post.isBookmarked;
      notifyListeners();

      try {
        if (post.isBookmarked) {
          await SocialService().bookmarkPost(postId);
        } else {
          await SocialService().unbookmarkPost(postId);
        }
      } catch (e) {
        // Rollback
        post.isBookmarked = originalStatus;
        notifyListeners();
        rethrow;
      }
    }
  }

  Future<void> addComment(String postId, Comment comment) async {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _posts[index].comments.add(comment);
      notifyListeners();

      try {
        await SocialService().addComment(postId, comment.text);

        // --- SISTEMA DE MENCIONES ---
        final RegExp mentionRegex = RegExp(r'@(\w+)');
        final Iterable<RegExpMatch> matches =
            mentionRegex.allMatches(comment.text);

        for (final match in matches) {
          final String mentionedUser = match.group(1) ?? '';
          if (mentionedUser.isNotEmpty &&
              mentionedUser != _currentUser.username) {
            addLocalNotification(
              _currentUser.username,
              'te ha mencionado en un comentario: "${comment.text}"',
              'mention',
              targetUser: mentionedUser,
            );
          }
        }

        // Notificar al autor si no somos nosotros
        if (_posts[index].username != _currentUser.username) {
          addLocalNotification(
            _currentUser.username,
            'ha comentado tu publicación: "${comment.text}"',
            'comment',
            targetUser: _posts[index].username,
          );
        }
      } catch (e) {
        debugPrint('Error al añadir comentario: $e');
      }
    }
  }

  Future<void> toggleCommentLike(String postId, Comment comment) async {
    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;
    final comments = _posts[postIndex].comments;
    final commentIndex = comments.indexWhere((c) => c.id == comment.id);
    if (commentIndex == -1) return;

    final target = comments[commentIndex];
    final wasLiked = target.isLiked;
    final prevLikes = target.likesCount;

    target.isLiked = !wasLiked;
    target.likesCount = (prevLikes + (wasLiked ? -1 : 1)).clamp(0, 1 << 31);
    notifyListeners();

    try {
      if (wasLiked) {
        await SocialService().unlikeComment(target.id);
      } else {
        await SocialService().likeComment(target.id);
      }
    } catch (e) {
      target.isLiked = wasLiked;
      target.likesCount = prevLikes;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteComment(String postId, Comment comment) async {
    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;
    final post = _posts[postIndex];
    final isAdmin = AuthService().isAdmin;
    final isCommentAuthor =
        comment.username.toLowerCase() == _currentUser.username.toLowerCase();
    final isPostOwner =
        post.username.toLowerCase() == _currentUser.username.toLowerCase();

    if (!(isAdmin || isCommentAuthor || isPostOwner)) {
      throw Exception('Sin permisos para eliminar este comentario');
    }

    final comments = post.comments;
    final commentIndex = comments.indexWhere((c) => c.id == comment.id);
    if (commentIndex == -1) return;
    final removed = comments.removeAt(commentIndex);
    notifyListeners();

    try {
      await SocialService().deleteComment(removed.id);
    } catch (e) {
      comments.insert(commentIndex, removed);
      notifyListeners();
      rethrow;
    }
  }

  void addPost(Post post) {
    _posts.insert(0, post);
    notifyListeners();
  }

  Future<void> deletePost(String postId) async {
    await SocialService().deletePost(postId);
    _posts.removeWhere((post) => post.id == postId);
    notifyListeners();
    await syncPosts();
    await syncProfile();
  }

  Future<void> report(String targetId, String type, String reason) async {
    await SocialService().report(targetId, type, reason);
  }

  Future<void> unfollowUser(String username) async {
    await SocialService().unfollowUser(username);
    updateFollowStatus(username, false);
  }

  Future<void> syncCurrentUser() async {
    if (!AuthService().isAuthenticated) return;

    final authUsername = AuthService().username?.trim() ?? '';
    if (authUsername.isNotEmpty &&
        _currentUser.username.trim().toLowerCase() !=
            authUsername.toLowerCase()) {
      _currentUser = _currentUser.copyWith(username: authUsername);
    }

    final targetUsername =
        authUsername.isNotEmpty ? authUsername : _currentUser.username.trim();
    if (targetUsername.isEmpty) return;

    try {
      final profileData = await SocialService().getProfile(targetUsername);
      var user = UserProfile.fromJson(profileData);

      // Aplicar persistencia local si el backend no tiene el dato actualizado
      final prefs = await SharedPreferences.getInstance();
      final localPrivate = prefs.getBool('is_private_${user.username}');
      if (localPrivate != null) {
        user = user.copyWith(isPrivate: localPrivate);
      }

      _currentUser = user;
      await AuthService().syncSessionFromProfile(_currentUser);
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing current user: $e');
    }
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    List<String>? sports,
    String? imagePath,
    String? username,
    bool? isPrivate,
  }) async {
    try {
      await SocialService().updateProfile(
        name: displayName,
        bio: bio,
        sport: (sports != null && sports.isNotEmpty) ? sports.join(',') : null,
        imagePath: imagePath,
        username: username,
        isPrivate: isPrivate,
      );

      // Actualizar el perfil completo desde la respuesta o localmente
      _currentUser = _currentUser.copyWith(
        displayName: displayName,
        bio: bio,
        sports: sports,
        userImage: imagePath,
        username: username,
        isPrivate: isPrivate,
      );

      // Asegurar que el campo 'sport' (string principal) se actualiza
      if (sports != null && sports.isNotEmpty) {
        _currentUser = _currentUser.copyWith(sport: sports.first);
      }

      // Persistir localmente como respaldo
      final prefs = await SharedPreferences.getInstance();
      if (isPrivate != null) {
        await prefs.setBool('is_private_${_currentUser.username}', isPrivate);
      }

      await AuthService().syncSessionFromProfile(_currentUser);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating profile in state: $e');
      rethrow;
    }
  }

  Future<void> syncSavedPosts() async {
    try {
      final savedData = await SocialService().getSavedPosts();
      for (var data in savedData) {
        final postId = data['id']?.toString() ?? '';
        final existingIndex = _posts.indexWhere((p) => p.id == postId);
        if (existingIndex != -1) {
          _posts[existingIndex].isBookmarked = true;
        } else {
          // If it's not in the feed, add it as a shadow post or just track bookmarked IDs
          // For now we just add it to posts if not exists to make it show up in saved tab
          _posts.add(
            Post(
              id: postId,
              username: data['authorUsername'] ?? 'usuario',
              userImage: ProfileAvatar.forPath(
                data['imagePath'] ?? data['userImage'],
                data['authorUsername']?.toString() ?? 'User',
              ),
              postImage: data['image']?.toString() ?? '',
              likes: data['likesCount'] ?? 0,
              caption: data['content'] ?? '',
              time: _formatDate(data['createdAt']),
              isLiked: data['isLiked'] == true,
              isBookmarked: true,
              comments: [],
            ),
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing saved posts: $e');
    }
  }

  Future<void> syncPosts() async {
    try {
      final postsData = await SocialService().getPosts();
      final List<Post> realPosts =
          postsData.map((data) => Post.fromJson(data)).toList();

      _posts.clear();
      _posts.addAll(realPosts);
      notifyListeners();
      for (var i = 0; i < math.min(5, _posts.length); i++) {
        _fetchCommentsForPost(_posts[i].id);
      }
    } catch (e) {
      debugPrint('Error syncing posts: $e');
    }
  }

  Future<void> _fetchCommentsForPost(String postId) async {
    try {
      final commentsData = await SocialService().getComments(postId);
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _posts[index].comments.clear();
        _posts[index].comments.addAll(
              commentsData.map(
                (c) => Comment(
                  id: c['id']?.toString() ?? '',
                  userId: c['userId']?.toString() ?? '',
                  username: c['authorUsername'] ?? 'usuario',
                  userImage: ProfileAvatar.forPath(
                    c['userImage'] ?? c['imagePath'],
                    c['authorUsername']?.toString() ?? 'Usuario',
                  ),
                  text: c['content'] ?? '',
                  time: _formatDate(c['createdAt']),
                  likesCount: (c['likesCount'] as num?)?.toInt() ?? 0,
                  isLiked: c['isLiked'] == true,
                ),
              ),
            );
        notifyListeners();
      }
    } catch (_) {}
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'Ahora';
    try {
      final date = DateTime.parse(dateStr.toString());
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Ahora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return 'Ahora';
    }
  }

  Future<void> _saveHighlights() async {
    final username = AuthService().username;
    if (username == null) return;

    final prefs = await SharedPreferences.getInstance();
    final data = _currentHighlights
        .map(
          (h) => {
            'id': h.id,
            'title': h.title,
            'coverImage': h.coverImage,
            'storyImages': h.storyImages,
          },
        )
        .toList();

    await prefs.setString('$_highlightsKeyPrefix$username', jsonEncode(data));
  }

  Future<void> _loadHighlights() async {
    final username = AuthService().username;
    if (username == null) return;

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_highlightsKeyPrefix$username');

    if (jsonStr != null) {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _currentHighlights.clear();
      for (var item in decoded) {
        _currentHighlights.add(
          Highlight(
            id: item['id'],
            title: item['title'],
            coverImage: item['coverImage'],
            storyImages: List<String>.from(item['storyImages']),
          ),
        );
      }
      notifyListeners();
    }
  }

  Future<void> _saveViewedStories() async {
    final username = AuthService().username;
    if (username == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_viewedStoriesKeyPrefix$username',
      _viewedStoryIds.toList(),
    );
  }

  Future<void> _loadViewedStories() async {
    final username = AuthService().username;
    if (username == null) return;

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('$_viewedStoriesKeyPrefix$username');
    if (list != null) {
      _viewedStoryIds.addAll(list);
      notifyListeners();
    }
  }

  Future<void> syncHighlights(String username) async {
    try {
      final data = await SocialService().getHighlights(username);
      final List<Highlight> highlights = data.map((item) {
        return Highlight(
          id: item['id'].toString(),
          title: item['title'],
          coverImage: item['image'],
          storyImages: item['storyImages'] != null
              ? List<String>.from(
                  item['storyImages'] is String
                      ? jsonDecode(item['storyImages'])
                      : item['storyImages'],
                )
              : [],
        );
      }).toList();

      if (username == _currentUser.username) {
        _currentHighlights.clear();
        _currentHighlights.addAll(highlights);
        _saveHighlights(); // Cache to local persistent prefs
      }
      _userHighlightsCache[username] = highlights;
      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing highlights for $username: $e');
    }
  }

  Future<void> updateDailyDuelPoints() async {
    try {
      final duelService = DuelService();
      final stats = await duelService.applyDailyTrainingPointsOnce();

      _duelPoints = stats['points'] ?? 0;
      _duelCompletedToday = stats['isCompletedToday'] ?? false;

      notifyListeners();
    } catch (e) {
      debugPrint('Error updating daily duel points: $e');
    }
  }

  Future<void> _loadChallengesPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = AuthService().username ?? 'guest';
      final String? joinedData = prefs.getString('joined_challenges_$username');
      if (joinedData != null) {
        final Map<String, dynamic> decoded = json.decode(joinedData);
        for (var challenge in _challenges) {
          if (decoded.containsKey(challenge['id'])) {
            challenge['isJoined'] = true;
            challenge['joinedAt'] = decoded[challenge['id']];
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading challenges persistence: $e');
    }
  }

  Future<void> _saveChallengesPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = AuthService().username ?? 'guest';
      final Map<String, String> joined = {};
      for (var challenge in _challenges) {
        if (challenge['isJoined'] == true) {
          joined[challenge['id']] =
              challenge['joinedAt'] ?? DateTime.now().toIso8601String();
        }
      }
      await prefs.setString('joined_challenges_$username', json.encode(joined));
    } catch (e) {
      debugPrint('Error saving challenges persistence: $e');
    }
  }

  void joinChallenge(String id) {
    final idx = _challenges.indexWhere((c) => c['id'] == id);
    if (idx != -1) {
      _challenges[idx]['isJoined'] = true;
      _challenges[idx]['participants']++;
      _challenges[idx]['joinedAt'] = DateTime.now().toIso8601String();

      _saveChallengesPersistence();

      addLocalNotification(
        'Sistema',
        '¡Te has unido con éxito al desafío: ${_challenges[idx]['title']}! 🚀',
        'challenge',
      );
      notifyListeners();
    }
  }

  void addLocalNotification(String username, String content, String type,
      {String? targetUser}) {
    final notification = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'username': username,
      'type': type,
      'content': content,
      'time': 'Ahora',
      'image': '',
      'read': false,
    };

    final target = targetUser ?? _currentUser.username;

    if (!_sessionNotifications.containsKey(target)) {
      _sessionNotifications[target] = [];
    }
    _sessionNotifications[target]!.insert(0, notification);

    // If it's for current user, also update the active list
    if (target == _currentUser.username) {
      _notifications.insert(0, notification);
      if (type == 'follow_request') {
        addFollowRequest(username);
      }
    }

    notifyListeners();
  }

  void addFollowRequest(String fromUsername) {
    if (!_followRequests.any((r) => r['username'] == fromUsername)) {
      _followRequests.add({
        'username': fromUsername,
        'time': 'Ahora',
        'image': '',
      });
      notifyListeners();
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _findFollowRequest(String username) {
    final needle = username.toLowerCase();
    for (final request in _followRequests) {
      if (request['username']?.toString().toLowerCase() == needle) {
        return request;
      }
    }
    return null;
  }

  Future<int> _resolveFollowRequesterId(
    String requesterUsername,
    int? senderUserId,
  ) async {
    int? requesterId = _asInt(_findFollowRequest(requesterUsername)?['id']);
    if (requesterId != null) return requesterId;

    await syncFollowRequests();
    requesterId = _asInt(_findFollowRequest(requesterUsername)?['id']);
    if (requesterId != null) return requesterId;

    if (senderUserId != null) return senderUserId;
    throw StateError('No se encontro la solicitud de @$requesterUsername');
  }

  Future<void> acceptFollowRequest(
    String requesterUsername, {
    int? senderUserId,
    String? notificationId,
  }) async {
    try {
      final requesterId = await _resolveFollowRequesterId(
        requesterUsername,
        senderUserId,
      );

      // Optimistic UI: remove the notification/request immediately.
      if (notificationId != null) {
        _notifications.removeWhere(
          (n) => n['id']?.toString() == notificationId,
        );
      } else {
        _notifications.removeWhere((n) =>
            (n['type']?.toString().toLowerCase() == 'follow_request') &&
            (n['username']?.toString() == requesterUsername));
      }

      _followRequests.removeWhere(
        (r) => r['username'] == requesterUsername || r['id'] == requesterId,
      );
      notifyListeners();

      await SocialService().acceptFollowRequest(requesterId);

      if (notificationId != null) {
        try {
          await SocialService().markNotificationAsRead(notificationId);
        } catch (_) {}
      }

      await syncFollowRequests();
      await syncNotifications();
      notifyListeners();
    } catch (e) {
      debugPrint('Error accepting follow request: $e');
      // Do not rethrow: keep the optimistic UI removal.
    }
  }

  Future<void> rejectFollowRequest(
    String requesterUsername, {
    int? senderUserId,
    String? notificationId,
  }) async {
    try {
      final requesterId = await _resolveFollowRequesterId(
        requesterUsername,
        senderUserId,
      );

      // Optimistic UI
      if (notificationId != null) {
        _notifications.removeWhere(
          (n) => n['id']?.toString() == notificationId,
        );
      } else {
        _notifications.removeWhere((n) =>
            (n['type']?.toString().toLowerCase() == 'follow_request') &&
            (n['username']?.toString() == requesterUsername));
      }

      _followRequests.removeWhere(
        (r) => r['username'] == requesterUsername || r['id'] == requesterId,
      );
      notifyListeners();

      await SocialService().rejectFollowRequest(requesterId);

      if (notificationId != null) {
        try {
          await SocialService().markNotificationAsRead(notificationId);
        } catch (_) {}
      }

      await syncFollowRequests();
      await syncNotifications();
      notifyListeners();
    } catch (e) {
      debugPrint('Error rejecting follow request: $e');
      // Do not rethrow: keep the optimistic UI removal.
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    final ids = _notifications
        .where((n) => n['read'] == false && n['id'] != null)
        .map((n) => n['id'].toString())
        .toList();
    _notifications.removeWhere((n) => n['read'] == false);
    notifyListeners();
    for (final id in ids) {
      try {
        await SocialService().markNotificationAsRead(id);
      } catch (_) {}
    }
    await syncNotifications();
  }

  Future<void> markNotificationAsRead(String id) async {
    _notifications.removeWhere((n) => n['id']?.toString() == id);
    notifyListeners();
    try {
      await SocialService().markNotificationAsRead(id);
    } catch (_) {}
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n['id']?.toString() == id);
    notifyListeners();
    try {
      await SocialService().deleteNotification(id);
    } catch (_) {}
  }

  void createChallenge(String title, String image) {
    _challenges.insert(0, {
      'id': 'c${_challenges.length + 1}',
      'title': title,
      'image': image,
      'participants': 1,
      'isJoined': true,
    });
    addLocalNotification(
      'Sistema',
      '¡Tu desafío "$title" ha sido creado con éxito!',
      'challenge',
    );
    notifyListeners();
  }

  void joinGroup(String id) {
    final idx = _groups.indexWhere((g) => g['id'] == id);
    if (idx != -1) {
      _groups[idx]['isJoined'] = true;
      _groups[idx]['members']++;
      addLocalNotification(
        'Sistema',
        '¡Te has unido al grupo: ${_groups[idx]['name']}!',
        'group',
      );
      notifyListeners();
    }
  }

  void saveRoutine(String id) {
    final idx = _routines.indexWhere((r) => r['id'] == id);
    if (idx != -1) {
      _routines[idx]['isSaved'] = true;
      addLocalNotification(
        'Sistema',
        'Has guardado la rutina "${_routines[idx]['title']}" en tu biblioteca.',
        'routine',
      );
      notifyListeners();
    }
  }

  void simulateInteraction() {
    final random = math.Random();
    final isLike = random.nextBool();
    if (isLike) {
      addLocalNotification(
        'mario_fitness',
        'le ha dado me gusta a tu publicación',
        'like',
      );
    } else {
      addLocalNotification('ana_runner', 'ha empezado a seguirte', 'follow');
    }
  }
}
