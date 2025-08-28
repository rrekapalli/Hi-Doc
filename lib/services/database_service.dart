import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../config/app_config.dart';
import '../models/health_entry.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import 'notification_service.dart';

/// Central persistence layer (SQLite local + backend HTTP helpers)
/// Clean implementation (legacy in‑memory paths removed).
class DatabaseService {
  static const _dbName = 'hi_doc.db';
  static const _dbVersion = 8; // bump when altering schema
  final NotificationService _notificationService;
  final _backendBaseUrl = AppConfig.backendBaseUrl;
  Database? _db;
  bool _initialized = false;

  DatabaseService({required NotificationService notificationService}) : _notificationService = notificationService;

  // ---- HTTP helpers ----
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService().getIdToken();
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Future<List<Map<String, dynamic>>> getProfiles() async {
    final r = await http.get(Uri.parse('$_backendBaseUrl/api/profiles'), headers: await _getAuthHeaders());
    if (r.statusCode != 200) throw Exception('Failed to load profiles');
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<List<Map<String, dynamic>>> getProfileMessages(String profileId) async {
    final r = await http.get(Uri.parse('$_backendBaseUrl/api/profiles/$profileId/messages'), headers: await _getAuthHeaders());
    if (r.statusCode != 200) throw Exception('Failed to load messages');
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<String> sendProfileMessage({required String profileId, required String content, String contentType = 'text'}) async {
    final r = await http.post(Uri.parse('$_backendBaseUrl/api/profiles/$profileId/messages'), headers: await _getAuthHeaders(), body: jsonEncode({'content': content, 'contentType': contentType}));
    if (r.statusCode != 200) throw Exception('Failed to send message');
    return (jsonDecode(r.body) as Map)['id'] as String;
  }

  Future<void> markProfileAsRead(String profileId) async {
    final r = await http.post(Uri.parse('$_backendBaseUrl/api/profiles/$profileId/read'), headers: await _getAuthHeaders());
    if (r.statusCode != 200) throw Exception('Failed to mark read');
  }

  Future<String> createProfile({String? title, required String type, required List<String> memberIds}) async {
    final r = await http.post(Uri.parse('$_backendBaseUrl/api/profiles'), headers: await _getAuthHeaders(), body: jsonEncode({'title': title, 'type': type, 'memberIds': memberIds}));
    if (r.statusCode != 200) throw Exception('Failed to create profile');
    return (jsonDecode(r.body) as Map)['id'] as String;
  }

  Future<List<Map<String, dynamic>>> searchUsers({String? query, int limit = 20}) async {
    final uri = Uri.parse('$_backendBaseUrl/api/users/search').replace(queryParameters: { if (query != null && query.isNotEmpty) 'query': query, 'limit': limit.toString() });
    final r = await http.get(uri, headers: await _getAuthHeaders());
    if (r.statusCode != 200) throw Exception('Failed to search users');
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<String> createExternalUser({required String name, String? email, String? phone}) async {
    final identifier = email ?? '$phone@phone.local';
    final r = await http.post(Uri.parse('$_backendBaseUrl/api/users/external'), headers: await _getAuthHeaders(), body: jsonEncode({'name': name, 'email': identifier, 'phone': phone, 'isExternal': true}));
    if (r.statusCode != 200) throw Exception('Failed to create external user');
    return (jsonDecode(r.body) as Map)['id'] as String;
  }

  // ---- Init ----
  Future<void> init() async {
    if (_initialized) return;
    try {
      if (kIsWeb) {
        final factory = databaseFactoryFfiWeb;
        _db = await factory.openDatabase(_dbName, options: OpenDatabaseOptions(
          version: _dbVersion,
          onCreate: (db, v) async => _onCreate(db),
          onUpgrade: (db, o, n) async => _onUpgrade(db, o, n),
        ));
      } else {
        final dir = await getApplicationDocumentsDirectory();
        _db = await openDatabase(p.join(dir.path, _dbName), version: _dbVersion, onCreate: (db, v) async => _onCreate(db), onUpgrade: (db, o, n) async => _onUpgrade(db, o, n));
      }
      _initialized = true;
    } catch (e, st) {
      debugPrint('DB init failed: $e\n$st');
      rethrow;
    }
  }

  Database _ensure() {
    final db = _db; if (!_initialized || db == null || !db.isOpen) throw StateError('DB not initialized'); return db; }

  // ---- Schema ----
  Future<void> _onCreate(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY, role TEXT, content TEXT, created_at INTEGER, person_id TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS health_entries (id TEXT PRIMARY KEY, person_id TEXT, timestamp INTEGER NOT NULL, type TEXT NOT NULL, data TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY, file_path TEXT, type TEXT, data TEXT, upload_date INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS reminders (id TEXT PRIMARY KEY, user_id TEXT, medication_id TEXT, title TEXT, time TEXT, message TEXT, repeat TEXT, days TEXT, active INTEGER DEFAULT 1)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS parsed_parameters (id TEXT PRIMARY KEY, unit TEXT, datetime TEXT, raw_json TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS medications (id TEXT PRIMARY KEY, name TEXT, dose REAL, dose_unit TEXT, frequency_per_day INTEGER, schedule_type TEXT, from_date INTEGER, to_date INTEGER, is_deleted INTEGER DEFAULT 0)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_medications_deleted ON medications(is_deleted);');
    await _createNormalizedMedicationTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // For simplicity re-run create (idempotent via IF NOT EXISTS) then targeted migrations
    await _onCreate(db);
    if (oldVersion < 8) await _migrateLegacy(db);
  }

  Future<void> _createNormalizedMedicationTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS medications_v2 (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, profile_id TEXT NOT NULL, name TEXT NOT NULL, notes TEXT, medication_url TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_medications_user_profile ON medications_v2(user_id, profile_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_medications_name ON medications_v2(name);');

    await db.execute('''CREATE TABLE IF NOT EXISTS medication_schedules (
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
      FOREIGN KEY(medication_id) REFERENCES medications_v2(id) ON DELETE CASCADE
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_schedules_medication ON medication_schedules(medication_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_schedules_active_window ON medication_schedules(start_date, end_date);');

    await db.execute('''CREATE TABLE IF NOT EXISTS medication_schedule_times (
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
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_times_schedule ON medication_schedule_times(schedule_id);');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_times_trigger ON medication_schedule_times(next_trigger_ts);');

    await db.execute('''CREATE TABLE IF NOT EXISTS medication_intake_logs (
      id TEXT PRIMARY KEY,
      schedule_time_id TEXT NOT NULL,
      taken_ts INTEGER NOT NULL,
      status TEXT NOT NULL,
      actual_dose_amount REAL,
      actual_dose_unit TEXT,
      notes TEXT,
      FOREIGN KEY(schedule_time_id) REFERENCES medication_schedule_times(id) ON DELETE CASCADE
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_intake_logs_time ON medication_intake_logs(taken_ts);');
  }

  Future<void> _migrateLegacy(Database db) async {
    try {
      final legacy = await db.query('medications');
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final med in legacy) {
        final id = med['id'] as String?; if (id == null) continue;
        final exists = await db.query('medications_v2', where: 'id = ?', whereArgs: [id]);
        if (exists.isNotEmpty) continue; // already migrated
        await db.insert('medications_v2', {
          'id': id,
            // Prototype placeholders until auth/profile routing is fully wired on client
          'user_id': 'prototype-user',
          'profile_id': 'default-profile',
          'name': med['name'],
          'notes': null,
          'medication_url': null,
          'created_at': now,
          'updated_at': now,
        });
      }
    } catch (e) {
      debugPrint('Legacy migration warn: $e');
    }
  }

  // ---- Helpers ----
  String _roleToString(MessageRole r) => switch (r) { MessageRole.user => 'user', MessageRole.assistant => 'assistant', MessageRole.system => 'system' };
  MessageRole _roleFromString(String r) => switch (r.toLowerCase()) { 'user' => MessageRole.user, 'assistant' || 'ai' || 'bot' => MessageRole.assistant, 'system' => MessageRole.system, _ => MessageRole.assistant };
  Map<String, dynamic> _parseMap(String s) => Map<String, dynamic>.from(jsonDecode(s) as Map);

  // ---- Messages ----
  Future<void> insertMessage(Message message, {String? personId}) async {
    final db = _ensure();
    await db.insert('messages', {
      'id': message.id,
      'role': _roleToString(message.role),
      'content': message.content,
      'created_at': message.createdAt.millisecondsSinceEpoch,
      'person_id': personId,
    });
  }

  Future<List<Message>> getMessages({int limit = 100, String? personId}) async {
    final db = _ensure();
    final rows = await db.query('messages', where: personId != null ? 'person_id = ?' : null, whereArgs: personId != null ? [personId] : null, orderBy: 'created_at ASC', limit: limit);
    return rows.map((r) => Message(id: r['id'] as String, role: _roleFromString(r['role'] as String), content: r['content'] as String, createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int))).toList();
  }

  // ---- Health Entries ----
  Future<void> insertEntry(HealthEntry entry) async {
    final db = _ensure();
    await db.insert('health_entries', {
      'id': entry.id,
      'person_id': entry.personId,
      'timestamp': entry.timestamp.millisecondsSinceEpoch,
      'type': entry.type.name,
      'data': jsonEncode(entry.toJson()),
    });
  }

  Future<List<HealthEntry>> listAllEntries({String? personId}) async {
    final db = _ensure();
    final rows = await db.query('health_entries', where: personId != null ? 'person_id = ?' : null, whereArgs: personId != null ? [personId] : null, orderBy: 'timestamp DESC');
    return rows.map((r) => HealthEntry.fromJson(_parseMap(r['data'] as String))).toList();
  }

  // ---- Reports ----
  Future<void> insertReport(Map<String, dynamic> report) async {
    final db = _ensure();
    await db.insert('reports', {
      'id': report['id'],
      'file_path': report['filePath'],
      'type': report['type'],
      'data': jsonEncode(report['data'] ?? {}),
      'upload_date': report['uploadDate'],
    });
  }

  Future<List<Map<String, dynamic>>> listReports() async {
    final db = _ensure();
    return db.query('reports', orderBy: 'upload_date DESC');
  }

  Future<void> deleteMedication(String id) async => _ensure().update('medications', {'is_deleted': 1}, where: 'id = ?', whereArgs: [id]);

  // ---- Legacy compatibility (to be removed after full migration) ----
  Future<void> updateMedication(Map<String, dynamic> medication) async {
    final db = _ensure();
    await db.update('medications', {
      'name': medication['name'],
      'dosage': medication['dosage'],
      'frequency_per_day': medication['frequency_per_day'],
      'schedule_type': medication['schedule_type'],
      'from_date': medication['from_date'],
      'to_date': medication['to_date'],
      'is_deleted': medication['is_deleted'] ?? 0,
    }, where: 'id = ?', whereArgs: [medication['id']]);
  }

  Future<List<Map<String, dynamic>>> getMedications({bool includeDeleted = false}) async {
    final db = _ensure();
    return db.query('medications', where: includeDeleted ? null : 'is_deleted = 0');
  }

  // ---- Normalized Medications (v2) ----
  Future<void> createMedicationV2(Map<String, dynamic> data) async => _ensure().insert('medications_v2', data, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateMedicationV2(Map<String, dynamic> data) async => _ensure().update('medications_v2', data, where: 'id = ?', whereArgs: [data['id']]);

  Future<List<Map<String, dynamic>>> listMedicationsV2({required String userId, required String profileId}) async => _ensure().query('medications_v2', where: 'user_id = ? AND profile_id = ?', whereArgs: [userId, profileId], orderBy: 'name ASC');

  Future<void> deleteMedicationV2(String id) async => _ensure().delete('medications_v2', where: 'id = ?', whereArgs: [id]);

  Future<void> createSchedule(Map<String, dynamic> data) async => _ensure().insert('medication_schedules', data, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateSchedule(Map<String, dynamic> data) async => _ensure().update('medication_schedules', data, where: 'id = ?', whereArgs: [data['id']]);

  Future<void> deleteSchedule(String id) async => _ensure().delete('medication_schedules', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getSchedules(String medicationId) async => _ensure().query('medication_schedules', where: 'medication_id = ?', whereArgs: [medicationId], orderBy: 'start_date ASC');

  Future<Map<String, dynamic>?> getScheduleById(String scheduleId) async { final rows = await _ensure().query('medication_schedules', where: 'id = ?', whereArgs: [scheduleId], limit: 1); return rows.isEmpty ? null : rows.first; }

  Future<void> createScheduleTime(Map<String, dynamic> data) async => _ensure().insert('medication_schedule_times', data, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateScheduleTime(Map<String, dynamic> data) async => _ensure().update('medication_schedule_times', data, where: 'id = ?', whereArgs: [data['id']]);

  Future<void> deleteScheduleTime(String id) async => _ensure().delete('medication_schedule_times', where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, dynamic>>> getScheduleTimes(String scheduleId) async => _ensure().query('medication_schedule_times', where: 'schedule_id = ?', whereArgs: [scheduleId], orderBy: 'sort_order ASC, time_local ASC');

  Future<void> insertIntakeLog(Map<String, dynamic> data) async => _ensure().insert('medication_intake_logs', data, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<Map<String, dynamic>>> listIntakeLogs(String medicationId, {int? fromTs, int? toTs}) async { final where = StringBuffer('ms.medication_id = ?'); final args = <Object?>[medicationId]; if (fromTs != null) { where.write(' AND mil.taken_ts >= ?'); args.add(fromTs); } if (toTs != null) { where.write(' AND mil.taken_ts <= ?'); args.add(toTs); } return _ensure().rawQuery('''SELECT mil.* FROM medication_intake_logs mil\n      JOIN medication_schedule_times mst ON mil.schedule_time_id = mst.id\n      JOIN medication_schedules ms ON mst.schedule_id = ms.id\n      WHERE ${where.toString()} ORDER BY mil.taken_ts DESC''', args); }

  // Generic raw query helper
  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<Object?>? args]) async => _ensure().rawQuery(sql, args);

  // ---- Reminders ----
  Future<void> insertReminder(Map<String, dynamic> reminder) async { const requiredFields = ['id','medication_id','title','time','repeat']; for (final f in requiredFields) { if (!reminder.containsKey(f)) throw Exception('Missing required field: $f'); } await _ensure().insert('reminders', reminder, conflictAlgorithm: ConflictAlgorithm.replace); if (!kIsWeb) { await _notificationService.scheduleMedicationReminder(id: reminder['id'] as String, title: reminder['title'] as String, message: (reminder['message'] as String?) ?? reminder['title'] as String, time: reminder['time'] as String, repeat: reminder['repeat'] as String, days: reminder['days'] as String?); } }

  Future<List<Map<String, dynamic>>> getRemindersByMedicationId(String medicationId) async => _ensure().query('reminders', where: 'medication_id = ?', whereArgs: [medicationId]);


  Future<void> updateMedicationReminders(String medicationId) async { if (kIsWeb) return; final reminders = await getRemindersByMedicationId(medicationId); for (final r in reminders) { await _notificationService.cancelNotification(r['id'] as String); } for (final r in reminders.where((x) => x['active'] == 1)) { await _notificationService.scheduleMedicationReminder(id: r['id'] as String, title: r['title'] as String, message: (r['message'] as String?) ?? r['title'] as String, time: r['time'] as String, repeat: r['repeat'] as String, days: r['days'] as String?); } }

  // Remove all reminders for a medication (used by schedule editor before re-creating times)
  Future<void> deleteRemindersForMedication(String medicationId) async {
    final db = _ensure();
    await db.delete('reminders', where: 'medication_id = ?', whereArgs: [medicationId]);
  }
}
