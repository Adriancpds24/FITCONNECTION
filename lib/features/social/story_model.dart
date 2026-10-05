class StoryModel {
  final String id;
  final String username;
  final String? userImage;
  final String? image;
  final bool isOwn;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isExpired;
  final DateTime? archivedAt;
  final String? deleteReason;
  bool? isLiked;

  StoryModel({
    required this.id,
    required this.username,
    required this.userImage,
    required this.image,
    required this.isOwn,
    required this.createdAt,
    required this.expiresAt,
    required this.isExpired,
    this.archivedAt,
    this.deleteReason,
    this.isLiked = false,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'].toString(),
      username: (json['username'] ?? 'usuario').toString(),
      userImage: json['userImage']?.toString(),
      image: json['image']?.toString(),
      isOwn: json['isOwn'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
      isExpired: json['isExpired'] == true,
      archivedAt: json['archivedAt'] != null
          ? DateTime.tryParse(json['archivedAt'].toString())
          : null,
      deleteReason: json['deleteReason']?.toString(),
    );
  }
}
