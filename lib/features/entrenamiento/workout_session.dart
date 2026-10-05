class WorkoutSession {
  final String? id;
  final int userId;
  final int? workoutId;
  final String? workoutTitle;
  final String? workoutDescription;
  final DateTime date;
  final bool isCompleted;
  final List<dynamic> exercisesList;
  final int durationSeconds;

  WorkoutSession({
    this.id,
    required this.userId,
    this.workoutId,
    this.workoutTitle,
    this.workoutDescription,
    required this.date,
    required this.isCompleted,
    required this.exercisesList,
    this.durationSeconds = 0,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'];
    DateTime parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else {
      parsedDate = DateTime.parse(rawDate.toString());
    }

    return WorkoutSession(
      id: json['id']?.toString(),
      userId: json['userId'] is int
          ? json['userId']
          : int.parse(json['userId'].toString()),
      workoutId: json['workoutId'],
      workoutTitle: json['workoutTitle'],
      workoutDescription: json['workoutDescription'],
      date: parsedDate,
      isCompleted: json['isCompleted'] == true,
      exercisesList: json['exercisesList'] ?? [],
      durationSeconds: json['durationSeconds'] is int
          ? json['durationSeconds'] as int
          : int.tryParse(json['durationSeconds']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'workoutId': workoutId,
      'workoutTitle': workoutTitle,
      'workoutDescription': workoutDescription,
      'date': date.toIso8601String().split('T')[0],
      'isCompleted': isCompleted,
      'exercisesList': exercisesList,
      'durationSeconds': durationSeconds,
    };
  }
}
