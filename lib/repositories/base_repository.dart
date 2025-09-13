/// Base repository interface that all data repositories should implement
/// Provides common CRUD operations with consistent patterns across the application
abstract class Repository<T> {
  /// Create a new entity and return its generated ID
  Future<String> create(T entity);

  /// Find entity by ID, returns null if not found
  Future<T?> findById(String id);

  /// Find all entities matching the given filters
  /// If filters is null or empty, returns all entities
  Future<List<T>> findAll({Map<String, dynamic>? filters});

  /// Update an existing entity by ID
  Future<void> update(String id, T entity);

  /// Delete entity by ID
  Future<void> delete(String id);

  /// Check if an entity exists by ID
  Future<bool> exists(String id);

  /// Count total entities matching the given filters
  Future<int> count({Map<String, dynamic>? filters});

  /// Get entities with pagination support
  Future<List<T>> findPaged({
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
    String? orderBy,
  });
}

/// Extension interface for repositories that need batch operations
abstract class BatchRepository<T> extends Repository<T> {
  /// Create multiple entities in a single transaction
  Future<List<String>> createBatch(List<T> entities);

  /// Update multiple entities in a single transaction
  Future<void> updateBatch(Map<String, T> entitiesById);

  /// Delete multiple entities by their IDs in a single transaction
  Future<void> deleteBatch(List<String> ids);
}

/// Interface for repositories that support user-scoped data
abstract class UserScopedRepository<T> extends Repository<T> {
  /// Find all entities for a specific user
  Future<List<T>> findByUserId(String userId, {Map<String, dynamic>? filters});

  /// Count entities for a specific user
  Future<int> countByUserId(String userId, {Map<String, dynamic>? filters});

  /// Delete all entities for a specific user
  Future<void> deleteByUserId(String userId);
}

/// Interface for repositories that support profile-scoped data
abstract class ProfileScopedRepository<T> extends UserScopedRepository<T> {
  /// Find all entities for a specific profile
  Future<List<T>> findByProfileId(
    String profileId, {
    Map<String, dynamic>? filters,
  });

  /// Count entities for a specific profile
  Future<int> countByProfileId(
    String profileId, {
    Map<String, dynamic>? filters,
  });

  /// Delete all entities for a specific profile
  Future<void> deleteByProfileId(String profileId);
}
