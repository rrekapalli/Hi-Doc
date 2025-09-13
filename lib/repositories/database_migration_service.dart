import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'local_database_service.dart';

/// Migration utilities for handling data migration from the old backend-dependent
/// database structure to the new offline-first structure
class DatabaseMigrationService {
  final LocalDatabaseService _localDb;

  DatabaseMigrationService(this._localDb);

  /// Migrate existing data to the new offline-first structure
  /// This will handle migration from the current DatabaseService structure
  Future<void> migrateFromLegacyDatabase() async {
    try {
      if (kDebugMode) {
        debugPrint(
          '[Migration] Starting migration from legacy database structure',
        );
      }

      // Check if legacy database exists and has data
      final hasLegacyData = await _hasLegacyData();
      if (!hasLegacyData) {
        if (kDebugMode) {
          debugPrint('[Migration] No legacy data found, skipping migration');
        }
        return;
      }

      await _localDb.transaction((txn) async {
        await _migrateUsers(txn);
        await _migrateMessages(txn);
        await _migrateHealthEntries(txn);
        await _migrateMedications(txn);
        await _migrateReports(txn);
      });

      if (kDebugMode) {
        debugPrint(
          '[Migration] Legacy database migration completed successfully',
        );
      }
    } catch (e, st) {
      debugPrint('[Migration] Failed to migrate legacy database: $e\n$st');
      rethrow;
    }
  }

  /// Check if there's existing legacy data that needs migration
  Future<bool> _hasLegacyData() async {
    try {
      final db = _localDb.database;

      // Check for existing data in key tables
      final tables = ['messages', 'health_entries', 'medications'];
      for (final table in tables) {
        try {
          final count = await db.rawQuery(
            'SELECT COUNT(*) as count FROM $table',
          );
          final tableCount = count.first['count'] as int? ?? 0;
          if (tableCount > 0) {
            return true;
          }
        } catch (e) {
          // Table might not exist yet, which is fine
          continue;
        }
      }

      return false;
    } catch (e) {
      debugPrint('[Migration] Error checking for legacy data: $e');
      return false;
    }
  }

  /// Migrate user data - create default user entries for existing data
  Future<void> _migrateUsers(Transaction txn) async {
    try {
      // Create a default user for existing data that doesn't have user association
      const defaultUserId = 'migrated-user';
      const defaultUserEmail = 'migrated@localhost';

      await txn.insert('users', {
        'id': defaultUserId,
        'email': defaultUserEmail,
        'name': 'Migrated User',
        'provider': 'local',
        'provider_id': defaultUserId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      if (kDebugMode) {
        debugPrint('[Migration] Created default user for migration');
      }
    } catch (e) {
      // User might already exist
      if (kDebugMode) {
        debugPrint('[Migration] Default user already exists or error: $e');
      }
    }
  }

  /// Migrate messages to include user_id
  Future<void> _migrateMedications(Transaction txn) async {
    try {
      // Check if medications need user_id
      final medications = await txn.query('medications');
      const defaultUserId = 'migrated-user';

      for (final med in medications) {
        if (med['user_id'] == null) {
          await txn.update(
            'medications',
            {'user_id': defaultUserId},
            where: 'id = ?',
            whereArgs: [med['id']],
          );
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[Migration] Updated ${medications.length} medications with user_id',
        );
      }
    } catch (e) {
      debugPrint('[Migration] Error migrating medications: $e');
    }
  }

  /// Migrate messages to include user_id
  Future<void> _migrateMessages(Transaction txn) async {
    try {
      // Check if messages need user_id
      final messages = await txn.query('messages');
      const defaultUserId = 'migrated-user';

      for (final msg in messages) {
        if (msg['user_id'] == null) {
          await txn.update(
            'messages',
            {'user_id': defaultUserId},
            where: 'id = ?',
            whereArgs: [msg['id']],
          );
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[Migration] Updated ${messages.length} messages with user_id',
        );
      }
    } catch (e) {
      debugPrint('[Migration] Error migrating messages: $e');
    }
  }

  /// Migrate health entries to include user_id
  Future<void> _migrateHealthEntries(Transaction txn) async {
    try {
      final healthEntries = await txn.query('health_entries');
      const defaultUserId = 'migrated-user';

      for (final entry in healthEntries) {
        if (entry['user_id'] == null) {
          await txn.update(
            'health_entries',
            {'user_id': defaultUserId},
            where: 'id = ?',
            whereArgs: [entry['id']],
          );
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[Migration] Updated ${healthEntries.length} health entries with user_id',
        );
      }
    } catch (e) {
      debugPrint('[Migration] Error migrating health entries: $e');
    }
  }

  /// Migrate reports to include user_id
  Future<void> _migrateReports(Transaction txn) async {
    try {
      final reports = await txn.query('reports');
      const defaultUserId = 'migrated-user';

      for (final report in reports) {
        if (report['user_id'] == null) {
          await txn.update(
            'reports',
            {'user_id': defaultUserId},
            where: 'id = ?',
            whereArgs: [report['id']],
          );
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[Migration] Updated ${reports.length} reports with user_id',
        );
      }
    } catch (e) {
      debugPrint('[Migration] Error migrating reports: $e');
    }
  }

  /// Export current database to a backup file
  Future<File> exportDatabaseBackup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final backupFile = File(
        p.join(
          tempDir.path,
          'hi_doc_backup_${DateTime.now().millisecondsSinceEpoch}.db',
        ),
      );

      if (kIsWeb) {
        // For web, we need to export the data as JSON since we can't access the file directly
        final exportData = await _exportDatabaseAsJson();
        await backupFile.writeAsString(jsonEncode(exportData));
      } else {
        // For native platforms, we can copy the database file directly
        final dbPath = await _getDatabasePath();
        final dbFile = File(dbPath);

        if (await dbFile.exists()) {
          await dbFile.copy(backupFile.path);
        } else {
          throw Exception('Database file not found at $dbPath');
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[Migration] Database backup exported to ${backupFile.path}',
        );
      }

      return backupFile;
    } catch (e) {
      debugPrint('[Migration] Failed to export database backup: $e');
      rethrow;
    }
  }

  /// Get the database file path for native platforms
  Future<String> _getDatabasePath() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'hi_doc.db');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, 'hi_doc.db');
    }
  }

  /// Export database as JSON for web platform
  Future<Map<String, dynamic>> _exportDatabaseAsJson() async {
    final db = _localDb.database;
    final exportData = <String, dynamic>{};

    // List of tables to export
    const tables = [
      'users',
      'messages',
      'health_entries',
      'medications',
      'medication_schedules',
      'medication_schedule_times',
      'medication_intake_logs',
      'reports',
      'reminders',
    ];

    for (final table in tables) {
      try {
        final rows = await db.query(table);
        exportData[table] = rows;
      } catch (e) {
        debugPrint('[Migration] Error exporting table $table: $e');
        exportData[table] = [];
      }
    }

    exportData['export_timestamp'] = DateTime.now().toIso8601String();
    exportData['version'] = 11;

    return exportData;
  }

  /// Restore database from a backup file
  Future<void> restoreDatabaseBackup(File backupFile) async {
    try {
      if (kDebugMode) {
        debugPrint(
          '[Migration] Starting database restore from ${backupFile.path}',
        );
      }

      if (kIsWeb) {
        // For web, restore from JSON export
        final jsonData = await backupFile.readAsString();
        final backupData = jsonDecode(jsonData) as Map<String, dynamic>;
        await _restoreDatabaseFromJson(backupData);
      } else {
        // For native platforms, replace the database file
        final dbPath = await _getDatabasePath();
        await backupFile.copy(dbPath);

        // Reinitialize the database
        await _localDb.close();
        await _localDb.initialize();
      }

      if (kDebugMode) {
        debugPrint('[Migration] Database restore completed successfully');
      }
    } catch (e) {
      debugPrint('[Migration] Failed to restore database backup: $e');
      rethrow;
    }
  }

  /// Restore database from JSON data (web platform)
  Future<void> _restoreDatabaseFromJson(Map<String, dynamic> backupData) async {
    await _localDb.transaction((txn) async {
      // Clear existing data
      const tables = [
        'ai_responses',
        'ai_usage',
        'backup_metadata',
        'sync_status',
        'reminders',
        'medication_intake_logs',
        'medication_schedule_times',
        'medication_schedules',
        'medications',
        'reports',
        'health_entries',
        'messages',
        'users',
      ];

      for (final table in tables) {
        try {
          await txn.delete(table);
        } catch (e) {
          // Table might not exist
        }
      }

      // Restore data
      for (final entry in backupData.entries) {
        if (entry.key.startsWith('export_') || entry.key == 'version') continue;

        final tableName = entry.key;
        final tableData = entry.value as List<dynamic>;

        for (final row in tableData) {
          try {
            await txn.insert(tableName, Map<String, dynamic>.from(row as Map));
          } catch (e) {
            debugPrint('[Migration] Error restoring row in $tableName: $e');
          }
        }
      }
    });
  }
}
