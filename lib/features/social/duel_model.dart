enum DuelStatus { active, pending, rejected }

class Duel {
  final int id;
  final int challengerId;
  final int challengedId;
  final String challengerName;
  final String challengedName;
  final String? challengerImage;
  final String? challengedImage;
  final DuelStatus status;
  final int challengerScore;
  final int challengedScore;
  final DateTime createdAt;

  Duel({
    required this.id,
    required this.challengerId,
    required this.challengedId,
    required this.challengerName,
    required this.challengedName,
    this.challengerImage,
    this.challengedImage,
    required this.status,
    this.challengerScore = 0,
    this.challengedScore = 0,
    required this.createdAt,
  });

  factory Duel.fromJson(Map<String, dynamic> json) {
    return Duel(
      id: json['id'],
      challengerId: json['challengerId'],
      challengedId: json['challengedId'],
      challengerName: json['challengerName'] ?? 'Usuario',
      challengedName: json['challengedName'] ?? 'Usuario',
      challengerImage: json['challengerImage'],
      challengedImage: json['challengedImage'],
      status: _parseStatus(json['status']),
      challengerScore: json['challengerScore'] ?? 0,
      challengedScore: json['challengedScore'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  static DuelStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return DuelStatus.active;
      case 'rejected':
        return DuelStatus.rejected;
      case 'pending':
      default:
        return DuelStatus.pending;
    }
  }

  String get statusText {
    switch (status) {
      case DuelStatus.active:
        return 'Activo';
      case DuelStatus.rejected:
        return 'Rechazado';
      case DuelStatus.pending:
        return 'Pendiente';
    }
  }
}
