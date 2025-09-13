import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/user.dart' as user_model;
import 'local_database_service.dart';
import 'repository_interfaces.dart';

/// Repository for managing user data in local SQLite database
class UserRepositoryImpl extends UserRepository {
  final LocalDatabaseService _databaseService;

  UserRepositoryImpl(this._databaseService);

  @override
  Future<String> create(User entity) async {
    final db = await _databaseService.database;
    final id = await db.insert('users', _userToDbMap(entity));
    return id.toString();
  }

  @override
  Future<User?> findById(String id) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [int.tryParse(id)],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return _userFromDbMap(result.first);
  }

  @override
  Future<List<User>> findAll({Map<String, dynamic>? filters}) async {
    final db = await _databaseService.database;
    final result = await db.query('users', orderBy: 'created_at DESC');
    return result.map((row) => _userFromDbMap(row)).toList();
  }

  @override
  Future<void> update(String id, User entity) async {
    final db = await _databaseService.database;
    await db.update(
      'users',
      _userToDbMap(entity),
      where: 'id = ?',
      whereArgs: [int.tryParse(id)],
    );
  }

  @override
  Future<void> delete(String id) async {
    final db = await _databaseService.database;
    await db.delete('users', where: 'id = ?', whereArgs: [int.tryParse(id)]);
  }

  @override
  Future<bool> exists(String id) async {
    final user = await findById(id);
    return user != null;
  }

  @override
  Future<int> count({Map<String, dynamic>? filters}) async {
    final db = await _databaseService.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    return (result.first['count'] as int?) ?? 0;
  }

  @override
  Future<List<User>> findPaged({
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
    String? orderBy,
  }) async {
    final db = await _databaseService.database;
    final offset = (page - 1) * limit;
    final result = await db.query(
      'users',
      limit: limit,
      offset: offset,
      orderBy: orderBy ?? 'created_at DESC',
    );
    return result.map((row) => _userFromDbMap(row)).toList();
  }

  @override
  Future<User?> findByEmail(String email) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return _userFromDbMap(result.first);
  }

  @override
  Future<User?> findByProvider(String provider, String providerId) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'users',
      where: 'provider = ? AND uid = ?',
      whereArgs: [provider, providerId],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return _userFromDbMap(result.first);
  }

  @override
  Future<List<User>> findAllByProvider(String provider) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'users',
      where: 'provider = ?',
      whereArgs: [provider],
      orderBy: 'created_at DESC',
    );
    return result.map((row) => _userFromDbMap(row)).toList();
  }

  /// Get current active user (most recently logged in)
  Future<User?> getCurrentUser() async {
    final db = await _databaseService.database;
    final result = await db.query(
      'users',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'last_login_at DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return _userFromDbMap(result.first);
  }

  /// Set user as active (and set others as inactive)
  Future<void> setActiveUser(int userId) async {
    final db = await _databaseService.database;

    await db.transaction((txn) async {
      // Set all users as inactive
      await txn.update('users', {'is_active': 0});
      // Set specified user as active
      await txn.update(
        'users',
        {'is_active': 1, 'last_login_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
  }

  /// Create or update user (upsert)
  Future<User> upsertUser(User user) async {
    final existingUser = await findByProvider(user.provider, user.uid);

    if (existingUser != null) {
      // Update existing user with new login time and data
      final updatedUser = existingUser.copyWith(
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        givenName: user.givenName,
        surname: user.surname,
        tenantId: user.tenantId,
        lastLoginAt: DateTime.now(),
        isActive: true,
        metadata: user.metadata,
      );

      await update(existingUser.id.toString(), updatedUser);
      await setActiveUser(existingUser.id!);
      return updatedUser.copyWith(id: existingUser.id);
    } else {
      // Create new user
      final id = await create(user);
      final newUser = user.copyWith(id: int.parse(id));
      await setActiveUser(int.parse(id));
      return newUser;
    }
  }

  /// Convert User model to database map
  Map<String, dynamic> _userToDbMap(User user) {
    return {
      if (user.id != null) 'id': user.id,
      'uid': user.uid,
      'email': user.email,
      'display_name': user.displayName,
      'photo_url': user.photoUrl,
      'given_name': user.givenName,
      'surname': user.surname,
      'provider': user.provider,
      'tenant_id': user.tenantId,
      'created_at': user.createdAt.toIso8601String(),
      'last_login_at': user.lastLoginAt?.toIso8601String(),
      'is_active': user.isActive ? 1 : 0,
      'metadata': user.metadata != null ? jsonEncode(user.metadata) : null,
    };
  }

  /// Convert database map to User model
  User _userFromDbMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int,
      uid: map['uid'] as String,
      email: map['email'] as String,
      displayName: map['display_name'] as String,
      photoUrl: map['photo_url'] as String?,
      givenName: map['given_name'] as String?,
      surname: map['surname'] as String?,
      provider: map['provider'] as String,
      tenantId: map['tenant_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.parse(map['last_login_at'] as String)
          : null,
      isActive: (map['is_active'] as int?) == 1,
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>?
          : null,
    );
  }
}
