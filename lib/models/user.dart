import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final int? id;
  final String uid; // Unique identifier from OAuth provider
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? givenName;
  final String? surname;
  final String provider; // 'google', 'microsoft'
  final String? tenantId; // For Microsoft users
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;
  final Map<String, dynamic>? metadata; // Additional provider-specific data

  const User({
    this.id,
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.givenName,
    this.surname,
    required this.provider,
    this.tenantId,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
    this.metadata,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// Create User from Google OAuth data
  factory User.fromGoogleOAuth(Map<String, dynamic> googleData) {
    return User(
      uid: googleData['id'] as String,
      email: googleData['email'] as String,
      displayName: googleData['displayName'] as String,
      photoUrl: googleData['photoUrl'] as String?,
      provider: 'google',
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      metadata: googleData,
    );
  }

  /// Create User from Microsoft OAuth data
  factory User.fromMicrosoftOAuth(Map<String, dynamic> microsoftData) {
    return User(
      uid: microsoftData['id'] as String,
      email: microsoftData['email'] as String,
      displayName: microsoftData['displayName'] as String,
      givenName: microsoftData['givenName'] as String?,
      surname: microsoftData['surname'] as String?,
      provider: 'microsoft',
      tenantId: microsoftData['tenantId'] as String?,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
      metadata: microsoftData,
    );
  }

  /// Create a copy of this User with some fields replaced
  User copyWith({
    int? id,
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? givenName,
    String? surname,
    String? provider,
    String? tenantId,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return User(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      givenName: givenName ?? this.givenName,
      surname: surname ?? this.surname,
      provider: provider ?? this.provider,
      tenantId: tenantId ?? this.tenantId,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, uid: $uid, email: $email, displayName: $displayName, provider: $provider)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.uid == uid && other.provider == provider;
  }

  @override
  int get hashCode => uid.hashCode ^ provider.hashCode;
}
