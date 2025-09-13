import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Enhanced database service for pure SQLite operations
/// Removes all HTTP dependencies and backend API calls
/// Provides a clean foundation for repository implementations
class LocalDatabaseService {
  static const _dbName = 'hi_doc.db';
  static const _dbVersion = 13; // Incremented for health analytics table

  Database? _db;
  bool _initialized = false;

  /// Initialize the local database with pure SQLite
  Future<void> initialize() async {
    if (_initialized && _db != null && _db!.isOpen) return;

    try {
      if (kIsWeb) {
        // Web platform using IndexedDB
        databaseFactory = databaseFactoryFfiWeb;
        _db = await openDatabase(
          _dbName,
          version: _dbVersion,
          onCreate: (db, version) => _onCreate(db),
          onUpgrade: (db, oldVersion, newVersion) =>
              _onUpgrade(db, oldVersion, newVersion),
        );
        if (kDebugMode) {
          debugPrint(
            '[LocalDB] Opened web IndexedDB database name=$_dbName version=$_dbVersion',
          );
        }
      } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        // Desktop platforms
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await getApplicationDocumentsDirectory();
        final fullPath = p.join(dir.path, _dbName);
        _db = await openDatabase(
          fullPath,
          version: _dbVersion,
          onCreate: (db, version) => _onCreate(db),
          onUpgrade: (db, oldVersion, newVersion) =>
              _onUpgrade(db, oldVersion, newVersion),
        );
        if (kDebugMode) {
          debugPrint(
            '[LocalDB] Opened desktop SQLite database $_dbName at $fullPath version=$_dbVersion',
          );
        }
      } else {
        // Mobile platforms (Android/iOS)
        final dir = await getApplicationDocumentsDirectory();
        final fullPath = p.join(dir.path, _dbName);
        _db = await openDatabase(
          fullPath,
          version: _dbVersion,
          onCreate: (db, version) => _onCreate(db),
          onUpgrade: (db, oldVersion, newVersion) =>
              _onUpgrade(db, oldVersion, newVersion),
        );
        if (kDebugMode) {
          debugPrint(
            '[LocalDB] Opened mobile SQLite database $_dbName at $fullPath version=$_dbVersion',
          );
        }
      }
      _initialized = true;

      if (kDebugMode) {
        try {
          await _debugDumpCounts();
        } catch (e) {
          debugPrint('[LocalDB] Debug dump failed: $e');
        }
      }
    } catch (e, st) {
      debugPrint('LocalDB init failed: $e\n$st');
      rethrow;
    }
  }

  /// Get the database instance, ensuring it's initialized
  Database get database {
    final db = _db;
    if (!_initialized || db == null || !db.isOpen) {
      throw StateError('LocalDB not initialized');
    }
    return db;
  }

  /// Execute operations within a transaction
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    return database.transaction(action);
  }

  /// Execute batch operations
  Future<List<Object?>> batch(void Function(Batch batch) operations) async {
    final batch = database.batch();
    operations(batch);
    return batch.commit();
  }

  /// Close the database connection
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _initialized = false;
    }
  }

  /// Create database schema
  Future<void> _onCreate(Database db) async {
    await _createUserTables(db);
    await _createHealthDataTables(db);
    await _createMedicationTables(db);
    await _createAITables(db);
    await _createBackupTables(db);
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (kDebugMode) {
      debugPrint('[LocalDB] Upgrading from version $oldVersion to $newVersion');
    }

    // Ensure all tables exist (idempotent)
    await _onCreate(db);

    // Apply migrations based on version
    if (oldVersion < 11) {
      await _migrateToV11(db);
    }
    if (oldVersion < 12) {
      await _migrateToV12(db);
    }
    if (oldVersion < 13) {
      await _migrateToV13(db);
    }
  }

  /// Create user management tables
  Future<void> _createUserTables(Database db) async {
    // Enhanced users table for OAuth user profiles
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT NOT NULL,
        email TEXT NOT NULL,
        display_name TEXT NOT NULL,
        photo_url TEXT,
        given_name TEXT,
        surname TEXT,
        provider TEXT NOT NULL, -- 'google' or 'microsoft'
        tenant_id TEXT, -- For Microsoft users
        created_at TEXT NOT NULL,
        last_login_at TEXT,
        is_active INTEGER DEFAULT 1,
        metadata TEXT, -- JSON string for additional provider-specific data
        UNIQUE(uid, provider)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_provider ON users(provider, uid);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active);
    ''');
  }

  /// Create health data tables
  Future<void> _createHealthDataTables(Database db) async {
    // Messages table for chat functionality
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        person_id TEXT,
        user_id TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_user_person ON messages(user_id, person_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
    ''');

    // Health entries table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_entries (
        id TEXT PRIMARY KEY,
        person_id TEXT,
        user_id TEXT,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        data TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_entries_user_person ON health_entries(user_id, person_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_entries_timestamp ON health_entries(timestamp);
    ''');

    // Reports table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        file_path TEXT,
        type TEXT,
        data TEXT,
        upload_date INTEGER,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reports_user ON reports(user_id);
    ''');

    // Health analytics table for trend analysis and insights
    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_analytics (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        person_id TEXT,
        vital_type TEXT,
        analysis_type TEXT NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER NOT NULL,
        data TEXT NOT NULL,
        insights TEXT NOT NULL,
        recommendations TEXT NOT NULL,
        risk_level TEXT,
        generated_at INTEGER NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_analytics_user ON health_analytics(user_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_analytics_type ON health_analytics(vital_type, analysis_type);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_analytics_date ON health_analytics(start_date, end_date);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_health_analytics_generated ON health_analytics(generated_at);
    ''');
  }

  /// Create medication management tables
  Future<void> _createMedicationTables(Database db) async {
    // Medications table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medications (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        name TEXT NOT NULL,
        notes TEXT,
        medication_url TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medications_user_profile ON medications(user_id, profile_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_medications_name ON medications(name);
    ''');

    // Medication schedules table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_schedules (
        id TEXT PRIMARY KEY,
        medication_id TEXT NOT NULL,
        schedule TEXT NOT NULL,
        frequency_per_day INTEGER,
        is_forever INTEGER DEFAULT 0,
        start_date INTEGER,
        end_date INTEGER,
        days_of_week TEXT,
        timezone TEXT,
        reminder_enabled INTEGER DEFAULT 1,
        FOREIGN KEY(medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_schedules_medication ON medication_schedules(medication_id);
    ''');

    // Medication schedule times table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_schedule_times (
        id TEXT PRIMARY KEY,
        schedule_id TEXT NOT NULL,
        time_local TEXT NOT NULL,
        dosage TEXT,
        dose_amount REAL,
        dose_unit TEXT,
        instructions TEXT,
        prn INTEGER DEFAULT 0,
        sort_order INTEGER,
        next_trigger_ts INTEGER,
        FOREIGN KEY(schedule_id) REFERENCES medication_schedules(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_schedule_times_schedule ON medication_schedule_times(schedule_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_schedule_times_trigger ON medication_schedule_times(next_trigger_ts);
    ''');

    // Medication intake logs table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_intake_logs (
        id TEXT PRIMARY KEY,
        schedule_time_id TEXT NOT NULL,
        taken_ts INTEGER NOT NULL,
        status TEXT NOT NULL,
        actual_dose_amount REAL,
        actual_dose_unit TEXT,
        notes TEXT,
        FOREIGN KEY(schedule_time_id) REFERENCES medication_schedule_times(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_intake_logs_time ON medication_intake_logs(taken_ts);
    ''');

    // Reminders table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        medication_id TEXT,
        title TEXT,
        time TEXT,
        message TEXT,
        repeat TEXT,
        days TEXT,
        active INTEGER DEFAULT 1,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Create AI service related tables
  Future<void> _createAITables(Database db) async {
    // AI usage tracking table for rate limiting
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        month_year TEXT NOT NULL, -- 'YYYY-MM' format
        request_count INTEGER DEFAULT 0,
        last_request_at INTEGER,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        UNIQUE(user_id, month_year)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_usage_user_month ON ai_usage(user_id, month_year);
    ''');

    // Detailed AI usage logs for tracking individual requests
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        month_year TEXT NOT NULL, -- 'YYYY-MM' format
        request_type TEXT DEFAULT 'chat',
        model TEXT,
        tokens_used INTEGER,
        request_id TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_usage_logs_user_month ON ai_usage_logs(user_id, month_year);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_usage_logs_timestamp ON ai_usage_logs(timestamp);
    ''');

    // Cached AI responses for offline access
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_responses (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        query_hash TEXT NOT NULL, -- Hash of the original query
        response_text TEXT NOT NULL,
        response_metadata TEXT, -- JSON metadata
        created_at INTEGER NOT NULL,
        expires_at INTEGER, -- Optional expiration
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_responses_user_hash ON ai_responses(user_id, query_hash);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_responses_expires ON ai_responses(expires_at);
    ''');
  }

  /// Create backup and sync related tables
  Future<void> _createBackupTables(Database db) async {
    // Backup metadata table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS backup_metadata (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        backup_date INTEGER NOT NULL,
        file_size INTEGER,
        cloud_provider TEXT NOT NULL, -- 'google_drive' or 'onedrive'
        cloud_file_id TEXT,
        cloud_file_path TEXT,
        checksum TEXT,
        version INTEGER DEFAULT 1,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_backup_user_date ON backup_metadata(user_id, backup_date);
    ''');

    // Sync status table for tracking data synchronization
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_status (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        last_sync_at INTEGER,
        sync_token TEXT, -- For incremental sync
        status TEXT DEFAULT 'pending', -- 'pending', 'syncing', 'completed', 'error'
        error_message TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        UNIQUE(user_id, table_name)
      )
    ''');
  }

  /// Migration for version 11 - refactoring to standalone app
  Future<void> _migrateToV11(Database db) async {
    try {
      // Add user_id columns to existing tables that don't have them
      await _addUserIdColumnIfNotExists(db, 'messages');
      await _addUserIdColumnIfNotExists(db, 'health_entries');
      await _addUserIdColumnIfNotExists(db, 'reports');

      if (kDebugMode) {
        debugPrint('[LocalDB] Migration to v11 completed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalDB] Migration to v11 failed: $e');
      }
      rethrow;
    }
  }

  /// Migration for version 12: Update users table for OAuth support
  Future<void> _migrateToV12(Database db) async {
    try {
      // Drop the old users table and recreate with new schema
      await db.execute('DROP TABLE IF EXISTS users');
      await _createUserTables(db);

      if (kDebugMode) {
        debugPrint(
          '[LocalDB] Migration to v12 completed - users table recreated for OAuth',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalDB] Migration to v12 failed: $e');
      }
      rethrow;
    }
  }

  /// Migration for version 13: Add health analytics table
  Future<void> _migrateToV13(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS health_analytics (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          person_id TEXT,
          vital_type TEXT,
          analysis_type TEXT NOT NULL,
          start_date INTEGER NOT NULL,
          end_date INTEGER NOT NULL,
          data TEXT NOT NULL,
          insights TEXT NOT NULL,
          recommendations TEXT NOT NULL,
          risk_level TEXT,
          generated_at INTEGER NOT NULL,
          FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_health_analytics_user ON health_analytics(user_id);
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_health_analytics_type ON health_analytics(vital_type, analysis_type);
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_health_analytics_date ON health_analytics(start_date, end_date);
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_health_analytics_generated ON health_analytics(generated_at);
      ''');

      if (kDebugMode) {
        debugPrint(
          '[LocalDB] Migration to v13 completed - health analytics table added',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalDB] Migration to v13 failed: $e');
      }
      rethrow;
    }
  }

  /// Helper to add user_id column if it doesn't exist
  Future<void> _addUserIdColumnIfNotExists(
    Database db,
    String tableName,
  ) async {
    try {
      // Check if column exists
      final columns = await db.rawQuery('PRAGMA table_info($tableName)');
      final hasUserIdColumn = columns.any((col) => col['name'] == 'user_id');

      if (!hasUserIdColumn) {
        await db.execute('ALTER TABLE $tableName ADD COLUMN user_id TEXT');
        if (kDebugMode) {
          debugPrint('[LocalDB] Added user_id column to $tableName');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LocalDB] Failed to add user_id to $tableName: $e');
      }
    }
  }

  /// Debug helper to dump table counts
  Future<void> _debugDumpCounts() async {
    final db = database;

    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) c FROM $table');
      return (rows.first['c'] as int?) ?? 0;
    }

    try {
      final users = await count('users');
      final messages = await count('messages');
      final healthEntries = await count('health_entries');
      final medications = await count('medications');
      final schedules = await count('medication_schedules');
      final aiUsage = await count('ai_usage');
      final backups = await count('backup_metadata');

      debugPrint(
        '[LocalDB] Table counts: users=$users messages=$messages health_entries=$healthEntries '
        'medications=$medications schedules=$schedules ai_usage=$aiUsage backups=$backups',
      );
    } catch (e) {
      debugPrint('[LocalDB] Failed to dump counts: $e');
    }
  }
}
