import 'package:rms/core/utils/profile_avatar.dart';

class Comment {
  final String id;
  final String userId;
  final String username;
  final String userImage;
  final String text;
  final String time;
  int likesCount;
  bool isLiked;

  Comment({
    required this.id,
    required this.userId,
    required this.username,
    required this.userImage,
    required this.text,
    required this.time,
    this.likesCount = 0,
    this.isLiked = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username'] ?? json['authorUsername'] ?? 'usuario',
      userImage: ProfileAvatar.forPath(
        json['userImage'] ?? json['imagePath'],
        json['username']?.toString() ??
            json['authorUsername']?.toString() ??
            'Usuario',
      ),
      text: json['text'] ?? json['content'] ?? '',
      time: json['time'] ?? json['createdAt'] ?? '',
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] ?? false,
    );
  }
}

class Post {
  final String id;
  final String username;
  final String userImage;
  final String postImage;
  final String caption;
  int likes;
  final String time;
  final DateTime? createdAt;
  final List<String> tags;
  bool isLiked;
  bool isBookmarked;
  final List<Comment> comments;

  Post({
    required this.id,
    required this.username,
    required this.userImage,
    required this.postImage,
    required this.caption,
    required this.likes,
    required this.time,
    this.createdAt,
    this.tags = const [],
    this.isLiked = false,
    this.isBookmarked = false,
    List<Comment>? comments,
  }) : comments = comments ?? [];

  static String formatRelativeTime(dynamic dateStr) {
    if (dateStr == null) return 'Ahora';
    final raw = dateStr.toString().trim();
    if (raw.isEmpty) return 'Ahora';
    if (!raw.contains('T') && !raw.contains('-')) {
      return raw;
    }
    try {
      final date = DateTime.parse(raw);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Ahora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return raw;
    }
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final username = (json['username'] ??
            json['authorUsername'] ??
            json['authorName'] ??
            'usuario')
        .toString();
    final createdAtRaw = json['createdAt']?.toString();
    final createdAt = DateTime.tryParse(createdAtRaw ?? '');

    return Post(
      id: json['id']?.toString() ?? '',
      username: username,
      userImage: ProfileAvatar.forPath(
        json['userImage'] ?? json['authorImage'] ?? json['imagePath'],
        username,
      ),
      postImage: (json['postImage'] ?? json['image'] ?? json['imageData'] ?? '')
          .toString(),
      caption: (json['caption'] ?? json['content'] ?? '').toString(),
      likes: (json['likes'] as num?)?.toInt() ??
          (json['likesCount'] as num?)?.toInt() ??
          0,
      time: formatRelativeTime(json['time'] ?? createdAtRaw),
      createdAt: createdAt,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isLiked: json['isLiked'] == true,
      isBookmarked: json['isBookmarked'] == true,
      comments: (json['comments'] as List?)
              ?.map((e) => Comment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toSharePayload() {
    return {
      'id': id,
      'username': username,
      'userImage': userImage,
      'postImage': postImage,
      'caption': caption,
      'likes': likes,
      'commentsCount': comments.length,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}

class Highlight {
  final String id;
  final String title;
  final String coverImage;
  final List<String> storyImages;

  Highlight({
    required this.id,
    required this.title,
    required this.coverImage,
    required this.storyImages,
  });
}

class UserProfile {
  final int? id;
  final String username;
  final String displayName;
  final String userImage;
  final String bio;
  final String sport;
  final String? email;
  int posts;
  int followers;
  int following;
  final List<String> sports;
  final List<Highlight> highlights;
  final bool isPrivate;

  // Gamification
  final int xp;
  final int level;
  final int fitcoins;
  final int streak;
  final int steps;
  final int burnedCalories;
  final int heartRate;
  final bool isRequested;

  UserProfile({
    this.id,
    required this.username,
    required this.displayName,
    required this.userImage,
    required this.bio,
    required this.sport,
    this.email,
    this.posts = 0,
    this.followers = 0,
    this.following = 0,
    this.sports = const [],
    this.highlights = const [],
    this.isPrivate = false,
    this.xp = 0,
    this.level = 1,
    this.fitcoins = 0,
    this.streak = 0,
    this.steps = 0,
    this.burnedCalories = 0,
    this.heartRate = 0,
    this.isRequested = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final sportString = json['sport'] ?? 'Fitness';
    final List<String> sports = [];
    for (var s in sportString.split(',')) {
      final trimmed = s.trim();
      if (trimmed.isNotEmpty) sports.add(trimmed);
    }

    final rawId = json['id'];
    final parsedId = rawId is int ? rawId : int.tryParse('$rawId');

    return UserProfile(
      id: parsedId,
      username: json['username'] ?? 'usuario',
      displayName: json['name'] ?? json['username'] ?? 'Usuario',
      userImage: ProfileAvatar.forPath(
        json['imagePath'] ?? json['userImage'],
        json['name']?.toString() ?? json['username']?.toString() ?? 'Usuario',
      ),
      bio: json['bio'] ?? '¡Hola! Estoy usando FitConnect',
      sport: sports.isNotEmpty ? sports.first : 'Fitness',
      sports: sports,
      posts: json['postsCount'] ?? 0,
      followers: json['followersCount'] ?? 0,
      following: json['followingCount'] ?? 0,
      isPrivate: json['isPrivate'] ?? false,
      xp: json['xp'] ?? 0,
      level: json['level'] ?? 1,
      fitcoins: json['fitcoins'] ?? 0,
      streak: json['streak'] ?? 0,
      steps: json['steps'] ?? 0,
      burnedCalories: json['burnedCalories'] ?? 0,
      heartRate: json['heartRate'] ?? 0,
      isRequested: json['isRequested'] ?? false,
    );
  }

  UserProfile copyWith({
    int? id,
    String? username,
    String? displayName,
    String? bio,
    String? sport,
    String? userImage,
    List<String>? sports,
    int? posts,
    int? followers,
    int? following,
    bool? isPrivate,
    int? xp,
    int? level,
    int? fitcoins,
    int? streak,
    int? steps,
    int? burnedCalories,
    int? heartRate,
    bool? isRequested,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      userImage: userImage ?? this.userImage,
      bio: bio ?? this.bio,
      sport: sport ?? this.sport,
      sports: sports ?? this.sports,
      email: email,
      posts: posts ?? this.posts,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      highlights: highlights,
      isPrivate: isPrivate ?? this.isPrivate,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      fitcoins: fitcoins ?? this.fitcoins,
      streak: streak ?? this.streak,
      steps: steps ?? this.steps,
      burnedCalories: burnedCalories ?? this.burnedCalories,
      heartRate: heartRate ?? this.heartRate,
      isRequested: isRequested ?? this.isRequested,
    );
  }
}
