import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/health_entry.dart';
import '../models/message.dart';
import 'notification_service.dart';
import '../services/auth_service.dart';

class DatabaseService {
  static const _dbName = 'hi_doc.db';
  static const _dbVersion = 7; // bump for medications table isDeleted flag
  Database? _db;
  bool _inMemory = false; // Web fallback
  bool _initialized = false;
  final NotificationService _notificationService;

  DatabaseService({required NotificationService notificationService})
      : _notificationService = notificationService;

  // In-memory stores for web fallback
  final List<HealthEntry> _entries = [];
  final List<Message> _messages = [];
  final List<Map<String, dynamic>> _medications = [];
  final List<Map<String, dynamic>> _reports = [];
  final List<Map<String, dynamic>> _reminders = [];

  Database _ensure() {
    if (!_initialized) {
      throw StateError('Database not initialized. Did you call init()?');
    }
    if (_db == null) {
      throw StateError('Database is null after initialization');
    }
    if (!_db!.isOpen) {
      throw StateError('Database is not open');
    }
    return _db!;
  }

  Map<String, dynamic> _parseMap(String s) {
    final decoded = jsonDecode(s);
    return Map<String, dynamic>.from(decoded as Map);
  }

  String _roleToString(MessageRole role) {
    switch (role) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  MessageRole _roleFromString(String role) {
    switch (role.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
      case 'ai':
      case 'bot':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.assistant;
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final authService = AuthService();
    final token = await authService.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
  }

  Future<void> init() async {
    if (_initialized) {
      debugPrint('Database already initialized');
      return;
    }

    try {
      if (kIsWeb) {
        debugPrint('SQLite not supported on web, using in-memory fallback storage');
        _inMemory = true;
        _initialized = true;
        return;
      }
      
      final appDir = await getApplicationDocumentsDirectory();
      final path = p.join(appDir.path, _dbName);
      debugPrint('Initializing database at path: $path');
      
      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, version) async {
          await _onCreate(db, version);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _onUpgrade(db, oldVersion, newVersion);
        },
        onOpen: (db) {
          debugPrint('Database opened successfully');
        },
      );
      
      _initialized = true;
      debugPrint('Database initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize database: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE health_entries (
      id TEXT PRIMARY KEY,
      person_id TEXT,
      timestamp INTEGER,
      type TEXT,
      data TEXT
    )''');

    await db.execute('''CREATE TABLE groups (
      id TEXT PRIMARY KEY,
      name TEXT,
      owner_user_id TEXT,
      data TEXT
    )''');

    await db.execute('''CREATE TABLE medications (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      dosage TEXT,
      schedule_type TEXT NOT NULL DEFAULT 'fixed',
      from_date INTEGER,
      to_date INTEGER,
      frequency_per_day INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    )''');
    
    // Add indexes for better performance
    await db.execute('CREATE INDEX idx_medications_is_deleted ON medications(is_deleted);');

    await db.execute('''CREATE TABLE reports (
      id TEXT PRIMARY KEY,
      file_path TEXT,
      type TEXT,
      data TEXT,
      upload_date INTEGER
    )''');

    await db.execute('''CREATE TABLE reminders (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      medication_id TEXT,
      title TEXT,
      time TEXT,
      message TEXT,
      repeat TEXT,
      days TEXT,
      active INTEGER DEFAULT 1
    )''');

    await db.execute('''CREATE TABLE parsed_parameters (
      id TEXT PRIMARY KEY,
      message_id TEXT,
      category TEXT,
      parameter TEXT,
      value TEXT,
      unit TEXT,
      datetime TEXT,
      raw_json TEXT
    )''');

    await db.execute('''CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      role TEXT,
      content TEXT,
      created_at INTEGER,
      person_id TEXT
    )''');
    
    await db.execute('''CREATE TABLE activities (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      name TEXT,
      duration_minutes INTEGER,
      distance_km REAL,
      intensity TEXT,
      calories_burned REAL,
      timestamp INTEGER,
      notes TEXT
    )''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''CREATE TABLE IF NOT EXISTS parsed_parameters (
        id TEXT PRIMARY KEY,
        message_id TEXT,
        category TEXT,
        parameter TEXT,
        value TEXT,
        unit TEXT,
        datetime TEXT,
        raw_json TEXT
      )''');
    }
    if (oldVersion < 3) {
      await db.execute('''CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        role TEXT,
        content TEXT,
        created_at INTEGER,
        person_id TEXT
      )''');
    }
    if (oldVersion < 4) {
      await db.execute('''CREATE TABLE IF NOT EXISTS activities (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        name TEXT,
        duration_minutes INTEGER,
        distance_km REAL,
        intensity TEXT,
        calories_burned REAL,
        timestamp INTEGER,
        notes TEXT
      )''');
    }
    if (oldVersion < 5) {
      // Drop and recreate reminders table with new schema
      await db.execute('DROP TABLE IF EXISTS reminders');
      await db.execute('''CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        medication_id TEXT,
        title TEXT,
        time TEXT,
        message TEXT,
        repeat TEXT,
        days TEXT,
        active INTEGER DEFAULT 1
      )''');
    }
    if (oldVersion < 6) {
      // Backup existing medications
      final medications = await db.query('medications');
      
      // Drop and recreate medications table with new schema
      await db.execute('DROP TABLE IF EXISTS medications');
      await db.execute('''CREATE TABLE medications (
        id TEXT PRIMARY KEY,
        name TEXT,
        dose REAL,
        dose_unit TEXT,
        frequency_per_day INTEGER,
        schedule_type TEXT CHECK(schedule_type IN ('fixed', 'as_needed', 'continuous')),
        from_date INTEGER,
        to_date INTEGER
      )''');
      
      // Migrate existing data
      for (final med in medications) {
        final startDate = med['start_date'] as int?;
        final durationDays = med['duration_days'] as int?;
        
        await db.insert('medications', {
          'id': med['id'],
          'name': med['name'],
          'dose': med['dose'],
          'dose_unit': med['dose_unit'],
          'frequency_per_day': med['frequency_per_day'],
          'schedule_type': durationDays == null ? 'continuous' : 'fixed',
          'from_date': startDate,
          'to_date': startDate != null && durationDays != null 
            ? startDate + (durationDays * 24 * 60 * 60 * 1000)  // Convert days to milliseconds
            : null,
        });
      }
    }
  }

  // --- Medication operations ---
  Future<void> insertMedication(Map<String, dynamic> med) async {
    if (_inMemory) {
      _medications.add(Map<String, dynamic>.from(med));
      return;
    }
    final db = _ensure();
    await db.insert('medications', {
      'id': med['id'],
      'name': med['name'],
      'dose': med['dose'],
      'dose_unit': med['doseUnit'],
      'frequency_per_day': med['frequencyPerDay'],
      'schedule_type': med['scheduleType'] ?? 'fixed',
      'from_date': (med['fromDate'] as DateTime?)?.millisecondsSinceEpoch,
      'to_date': (med['toDate'] as DateTime?)?.millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> listMedications() async {
    if (_inMemory) {
      return List<Map<String, dynamic>>.from(_medications);
    }
    final db = _ensure();
    final rows = await db.query('medications', orderBy: 'start_date DESC');
    return rows;
  }

  Future<void> deleteMedication(String id) async {
    debugPrint('Soft deleting medication with ID: $id');
    try {
      if (_inMemory) {
        final index = _medications.indexWhere((med) => med['id'] == id);
        if (index != -1) {
          _medications[index] = {
            ..._medications[index],
            'is_deleted': 1,
          };
        }
        return;
      }
      final db = _ensure();
      
      // Soft delete the medication by setting is_deleted flag
      await db.update(
        'medications',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      
      debugPrint('Successfully soft deleted medication');
    } catch (e) {
      debugPrint('Failed to soft delete medication: $e');
      rethrow;
    }
  }

  Future<void> updateMedication(Map<String, dynamic> medication) async {
    debugPrint('Updating/Creating medication with ID: ${medication['id']}');
    try {
      if (_inMemory) {
        final headers = {
          ...await _getAuthHeaders(),
          'Content-Type': 'application/json',
        };

        // First try to create the medication
        final createResponse = await http.post(
          Uri.parse('${AppConfig.backendBaseUrl}/api/medications'),
          headers: headers,
          body: json.encode(medication),
        );

        if (createResponse.statusCode != 201) {
          // If creation fails, try updating
          final updateResponse = await http.put(
            Uri.parse('${AppConfig.backendBaseUrl}/api/medications/${medication['id']}'),
            headers: headers,
            body: json.encode(medication),
          );

          if (updateResponse.statusCode != 200) {
            throw Exception('Failed to save medication: ${updateResponse.body}');
          }
        }

        final index = _medications.indexWhere((med) => med['id'] == medication['id']);
        if (index != -1) {
          _medications[index] = Map<String, dynamic>.from(medication);
        } else {
          _medications.add(Map<String, dynamic>.from(medication));
        }
        return;
      }

      // Fallback to direct database update if not in memory mode
      final db = _ensure();
      final updateData = {
        'name': medication['name'],
        'dosage': medication['dosage'],
        'frequency_per_day': medication['frequency_per_day'],
        'schedule_type': medication['schedule_type'],
        'from_date': medication['from_date'],
        'to_date': medication['to_date'],
        'is_deleted': medication['is_deleted'] ?? 0,
        'user_id': medication['user_id'] ?? 'prototype-user-12345',
      };
      
      await db.update(
        'medications',
        updateData,
        where: 'id = ? AND user_id = ?',
        whereArgs: [medication['id'], medication['user_id'] ?? 'prototype-user-12345'],
      );
      
      debugPrint('Successfully updated medication');
    } catch (e) {
      debugPrint('Failed to update medication: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getMedications({bool includeDeleted = false}) async {
    if (_inMemory) {
      try {
        final response = await http.get(
          Uri.parse('${AppConfig.backendBaseUrl}/api/medications'),
          headers: await _getAuthHeaders(),
        );
        
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          final medications = data.cast<Map<String, dynamic>>();
          if (!includeDeleted) {
            return medications.where((med) => med['is_deleted'] != 1).toList();
          }
          return medications;
        } else {
          debugPrint('Failed to fetch medications: ${response.statusCode}');
          return [];
        }
      } catch (e) {
        debugPrint('Failed to fetch medications: $e');
        return [];
      }
    }
    
    try {
      final db = _ensure();
      final rows = await db.query(
        'medications',
        orderBy: 'start_date DESC',
      );
      return rows;
    } catch (e) {
      debugPrint('Failed to fetch medications: $e');
      return [];
    }
  }

  // --- Reminder operations ---
  Future<List<Map<String, dynamic>>> getRemindersByMedicationId(String medicationId) async {
    if (_inMemory) {
      return _reminders.where((r) => r['medication_id'] == medicationId && r['active'] == 1).toList();
    }
    final db = _ensure();
    final rows = await db.query(
      'reminders',
      where: 'medication_id = ? AND active = 1',
      whereArgs: [medicationId],
      orderBy: 'time ASC',
    );
    return rows;
  }

  Future<void> deleteRemindersForMedication(String medicationId) async {
    if (_inMemory) {
      _reminders.removeWhere((r) => r['medication_id'] == medicationId);
      return;
    }
    final db = _ensure();
    await db.delete(
      'reminders',
      where: 'medication_id = ?',
      whereArgs: [medicationId],
    );
  }

  Future<void> insertReminder(Map<String, dynamic> reminder) async {
    final reminderId = const Uuid().v4();
    debugPrint('Starting reminder insertion for ID: $reminderId');

    // Validate required fields
    final requiredFields = ['user_id', 'medication_id', 'title', 'time', 'message', 'repeat'];
    for (final field in requiredFields) {
      if (reminder[field] == null) {
        throw Exception('Missing required field: $field');
      }
    }

    // Prepare reminder data
    final reminderData = {
      'id': reminderId,
      'user_id': reminder['user_id'],
      'medication_id': reminder['medication_id'],
      'title': reminder['title'],
      'time': reminder['time'],
      'message': reminder['message'],
      'repeat': reminder['repeat'],
      'days': reminder['days'],
      'active': reminder['active'] ?? 1,
    };

    try {
      if (_inMemory) {
        debugPrint('Adding reminder to in-memory storage: $reminderData');
        _reminders.add(reminderData);
        debugPrint('Reminder added to in-memory storage successfully');
      } else {
        final db = _ensure();
        debugPrint('Inserting reminder into database: $reminderData');
        await db.insert(
          'reminders',
          reminderData,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        debugPrint('Reminder successfully inserted into SQLite database');
      }

      // Schedule the notification (only for mobile)
      if (!kIsWeb) {
        try {
          debugPrint('Scheduling notification for reminder');
          await _notificationService.scheduleMedicationReminder(
            id: reminderId,
            title: reminder['title'],
            message: reminder['message'],
            time: reminder['time'],
            repeat: reminder['repeat'],
            days: reminder['days'],
          );
          debugPrint('Notification scheduled successfully');
        } catch (e) {
          debugPrint('Failed to schedule notification: $e');
          // Continue even if notification fails as the reminder is saved
        }
      } else {
        debugPrint('Skipping notification scheduling in web mode');
      }
    } catch (e) {
      debugPrint('Failed to insert reminder: $e');
      rethrow;
    }
  }

  Future<void> updateMedicationReminders(String medicationId) async {
    if (kIsWeb) {
      debugPrint('Skipping notification updates in web mode');
      return;
    }

    final reminders = await getRemindersByMedicationId(medicationId);

    // Cancel existing notifications
    for (final reminder in reminders) {
      await _notificationService.cancelNotification(reminder['id'] as String);
    }

    // Schedule new notifications for active reminders
    for (final reminder in reminders.where((r) => r['active'] == 1)) {
      await _notificationService.scheduleMedicationReminder(
        id: reminder['id'] as String,
        title: reminder['title'] as String,
        message: reminder['message'] as String,
        time: reminder['time'] as String,
        repeat: reminder['repeat'] as String,
        days: reminder['days'] as String?,
      );
    }
  }

  // --- Report operations ---
  Future<void> insertReport(Map<String, dynamic> report) async {
    if (_inMemory) {
      _reports.add(Map<String, dynamic>.from(report));
      return;
    }
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
    if (_inMemory) {
      return List<Map<String, dynamic>>.from(_reports);
    }
    final db = _ensure();
    return db.query('reports', orderBy: 'upload_date DESC');
  }

  // --- Entry operations ---
  Future<void> insertEntry(HealthEntry entry) async {
    if (_inMemory) {
      _entries.add(entry);
      return;
    }
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
    if (_inMemory) {
      final list = personId == null ? _entries : _entries.where((e) => e.personId == personId).toList();
      return List<HealthEntry>.from(list)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final db = _ensure();
    final rows = await db.query('health_entries',
        where: personId != null ? 'person_id = ?' : null,
        whereArgs: personId != null ? [personId] : null,
        orderBy: 'timestamp DESC');
    return rows.map((r) {
      final dataStr = r['data'] as String;
      final jsonMap = _parseMap(dataStr);
      return HealthEntry.fromJson(jsonMap);
    }).toList();
  }

  // --- Message operations ---
  Future<void> insertMessage(Message message, {String? personId}) async {
    if (_inMemory) {
      _messages.add(message);
      return;
    }
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
    if (_inMemory) {
      final list = personId == null
          ? _messages
          : _messages.where((m) => m.id.contains(personId)).toList();
      final sorted = List<Message>.from(list)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted.take(limit).toList();
    }
    final db = _ensure();
    final rows = await db.query('messages',
        where: personId != null ? 'person_id = ?' : null,
        whereArgs: personId != null ? [personId] : null,
        orderBy: 'created_at ASC',
        limit: limit);
    return rows.map((r) => Message(
      id: r['id'] as String,
      role: _roleFromString(r['role'] as String),
      content: r['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    )).toList();
  }
}
