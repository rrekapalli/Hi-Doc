class Activity {
  final String id;
  final String userId;
  final String profileId;
  final String name;
  final int? durationMinutes;
  final double? distanceKm;
  final String? intensity;
  final double? caloriesBurned;
  final DateTime timestamp;
  final String? notes;

  Activity({
    required this.id,
    required this.userId,
  required this.profileId,
    required this.name,
    required this.timestamp,
    this.durationMinutes,
    this.distanceKm,
    this.intensity,
    this.caloriesBurned,
    this.notes,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
  double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }
    // Robust timestamp parsing (may arrive as int or string)
    final rawTs = json['timestamp'];
    int? tsInt;
    if (rawTs is int) {
      tsInt = rawTs;
    } else if (rawTs is String) {
      tsInt = int.tryParse(rawTs);
    }
    // Fallback: if it looks like seconds (10 digits) convert to ms
    if (tsInt != null && tsInt < 20000000000) { // < ~Sat Nov 20 2603 in ms if seconds -> heuristic
      // Distinguish seconds vs ms: if less than year ~ 3000 in ms timeframe
      if (tsInt < 100000000000) { // very likely seconds (11 digits would be ~ year 5138 ms)
        tsInt = tsInt * 1000;
      }
    }
    final ts = tsInt ?? DateTime.now().millisecondsSinceEpoch;

    return Activity(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? 'unknown-user',
  profileId: json['profile_id'] as String? ?? 'default-profile',
      name: json['name'] as String? ?? 'Activity',
      durationMinutes: json['duration_minutes'] is int ? json['duration_minutes'] as int : int.tryParse('${json['duration_minutes']}'),
  distanceKm: toDouble(json['distance_km']),
      intensity: json['intensity'] as String?,
  caloriesBurned: toDouble(json['calories_burned']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
  'profile_id': profileId,
        'name': name,
        'duration_minutes': durationMinutes,
        'distance_km': distanceKm,
        'intensity': intensity,
        'calories_burned': caloriesBurned,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'notes': notes,
      };

  Activity copyWith({
    String? id,
    String? userId,
  String? profileId,
    String? name,
    int? durationMinutes,
    double? distanceKm,
    String? intensity,
    double? caloriesBurned,
    DateTime? timestamp,
    String? notes,
  }) => Activity(
        id: id ?? this.id,
        userId: userId ?? this.userId,
  profileId: profileId ?? this.profileId,
        name: name ?? this.name,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        distanceKm: distanceKm ?? this.distanceKm,
        intensity: intensity ?? this.intensity,
        caloriesBurned: caloriesBurned ?? this.caloriesBurned,
        timestamp: timestamp ?? this.timestamp,
        notes: notes ?? this.notes,
      );

  @override
  String toString() => 'Activity($name, ${timestamp.toIso8601String()})';
}
