import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../config/app_config.dart';
import '../models/health_entry.dart';
import '../models/message.dart';
import '../services/auth_service.dart';

class DatabaseService {
  static const _dbName = 'hi_doc.db';
  static const _dbVersion = 4; // bump for activities table
  Database? _db;
  bool _inMemory = false; // Web fallback

  // In-memory stores for web fallback
  final List<HealthEntry> _entries = [];
  final List<Message> _messages = [];
  final List<Map<String, dynamic>> _medications = [];
  final List<Map<String, dynamic>> _reports = [];
  final List<Map<String, dynamic>> _reminders = [];

  Future<void> init() async {
    if (kIsWeb) {
      debugPrint('SQLite not supported on web, using in-memory fallback storage');
      _inMemory = true;
      return;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final path = p.join(appDir.path, _dbName);
    _db = await openDatabase(path, version: _dbVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE health_entries (\n      id TEXT PRIMARY KEY,\n      person_id TEXT,\n      timestamp INTEGER,\n      type TEXT,\n      data TEXT\n    )''');
    await db.execute('''CREATE TABLE groups (\n      id TEXT PRIMARY KEY,\n      name TEXT,\n      owner_user_id TEXT,\n      data TEXT\n    )''');
    await db.execute('''CREATE TABLE medications (\n      id TEXT PRIMARY KEY,\n      name TEXT,\n      dose REAL,\n      dose_unit TEXT,\n      frequency_per_day INTEGER,\n      duration_days INTEGER,\n      start_date INTEGER\n    )''');
    await db.execute('''CREATE TABLE reports (\n      id TEXT PRIMARY KEY,\n      file_path TEXT,\n      type TEXT,\n      data TEXT,\n      upload_date INTEGER\n    )''');
    await db.execute('''CREATE TABLE reminders (\n      id TEXT PRIMARY KEY,\n      title TEXT,\n      body TEXT,\n      scheduled_at INTEGER\n    )''');
    await db.execute('''CREATE TABLE parsed_parameters (\n      id TEXT PRIMARY KEY,\n      message_id TEXT,\n      category TEXT,\n      parameter TEXT,\n      value TEXT,\n      unit TEXT,\n      datetime TEXT,\n      raw_json TEXT\n    )''');
    await db.execute('''CREATE TABLE messages (\n      id TEXT PRIMARY KEY,\n      role TEXT,\n      content TEXT,\n      created_at INTEGER,\n      person_id TEXT\n    )''');
    
    await db.execute('''CREATE TABLE activities (\n      id TEXT PRIMARY KEY,\n      user_id TEXT,\n      name TEXT,\n      duration_minutes INTEGER,\n      distance_km REAL,\n      intensity TEXT,\n      calories_burned REAL,\n      timestamp INTEGER,\n      notes TEXT\n    )''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''CREATE TABLE IF NOT EXISTS parsed_parameters (\n        id TEXT PRIMARY KEY,\n        message_id TEXT,\n        category TEXT,\n        parameter TEXT,\n        value TEXT,\n        unit TEXT,\n        datetime TEXT,\n        raw_json TEXT\n      )''');
    }
    if (oldVersion < 3) {
      await db.execute('''CREATE TABLE IF NOT EXISTS messages (\n        id TEXT PRIMARY KEY,\n        role TEXT,\n        content TEXT,\n        created_at INTEGER,\n        person_id TEXT\n      )''');
    }
    if (oldVersion < 4) {
      await db.execute('''CREATE TABLE IF NOT EXISTS activities (\n        id TEXT PRIMARY KEY,\n        user_id TEXT,\n        name TEXT,\n        duration_minutes INTEGER,\n        distance_km REAL,\n        intensity TEXT,\n        calories_burned REAL,\n        timestamp INTEGER,\n        notes TEXT\n      )''');
    }
  }

  Future<void> insertParsedParameters(String messageId, List<Map<String, dynamic>> params) async {
    if (_inMemory) {
      // For web fallback simply append to entries as notes summarizing.
      for (final p in params) {
        _entries.add(HealthEntry.note(id: p['id'], timestamp: DateTime.now(), note: '${p['parameter']}: ${p['value']}${p['unit'] != null ? ' '+p['unit'] : ''}', personId: null));
      }
      return;
    }
    final db = _ensure();
    final batch = db.batch();
    for (final p in params) {
      batch.insert('parsed_parameters', {
        'id': p['id'],
        'message_id': messageId,
        'category': p['category'],
        'parameter': p['parameter'],
        'value': p['value'],
        'unit': p['unit'],
        'datetime': p['datetime'],
        'raw_json': p['raw_json'],
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String,dynamic>>> listParsedParameters({String? messageId}) async {
    if (_inMemory) {
      return []; // not stored separately in-memory
    }
    final db = _ensure();
    return db.query('parsed_parameters', where: messageId != null ? 'message_id = ?' : null, whereArgs: messageId != null ? [messageId] : null, orderBy: 'rowid DESC');
  }

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

  Future<void> updateEntry(HealthEntry entry) async {
    if (_inMemory) {
      final idx = _entries.indexWhere((e) => e.id == entry.id);
      if (idx != -1) {
        _entries[idx] = entry; // replace in-memory
      }
      return;
    }
    final db = _ensure();
    await db.update('health_entries', {
      'person_id': entry.personId,
      'timestamp': entry.timestamp.millisecondsSinceEpoch,
      'type': entry.type.name,
      'data': jsonEncode(entry.toJson()),
    }, where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<List<HealthEntry>> getRecentEntries({int limit = 50, String? personId}) async {
    if (_inMemory) {
      final list = personId == null
          ? _entries
          : _entries.where((e) => e.personId == personId).toList();
      return list
          .sortedByTimestampDesc()
          .take(limit)
          .toList();
    }
    final db = _ensure();
    final rows = await db.query('health_entries',
        where: personId != null ? 'person_id = ?' : null,
        whereArgs: personId != null ? [personId] : null,
        orderBy: 'timestamp DESC',
        limit: limit);
    return rows.map((r) {
      final dataStr = r['data'] as String;
      final jsonMap = _parseMap(dataStr);
      return HealthEntry.fromJson(jsonMap);
    }).toList();
  }

  Future<List<HealthEntry>> listAllEntries({String? personId}) async {
    if (_inMemory) {
      final list = personId == null ? _entries : _entries.where((e) => e.personId == personId).toList();
      return list.sortedByTimestampDesc();
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

  Map<String, dynamic> _parseMap(String s) {
    final decoded = jsonDecode(s);
    return Map<String, dynamic>.from(decoded as Map);
  }

  // --- Medication simplified operations (store as part of health if needed later) ---
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
      'duration_days': med['durationDays'],
      'start_date': (med['startDate'] as DateTime?)?.millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> listMedications() async {
    if (_inMemory) {
      return List<Map<String, dynamic>>.from(_medications);
    }
    final db = _ensure();
    final rows = await db.query('medications', orderBy: 'start_date DESC');
    return rows.map((r) => r).toList();
  }

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

  Future<void> insertReminder(Map<String, dynamic> reminder) async {
    if (_inMemory) {
      _reminders.add(Map<String, dynamic>.from(reminder));
      return;
    }
    final db = _ensure();
    await db.insert('reminders', {
      'id': reminder['id'],
      'title': reminder['title'],
      'body': reminder['body'],
      'scheduled_at': reminder['scheduledAt'],
    });
  }

  Future<List<Map<String, dynamic>>> listReminders() async {
    if (_inMemory) {
      return List<Map<String, dynamic>>.from(_reminders);
    }
    final db = _ensure();
    return db.query('reminders', orderBy: 'scheduled_at ASC');
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

  Future<List<Map<String, dynamic>>> getMedications() async {
    if (_inMemory) {
      try {
        final response = await http.get(
          Uri.parse('${AppConfig.backendBaseUrl}/api/medications'),
          headers: await _getAuthHeaders(),
        );
        
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          return data.cast<Map<String, dynamic>>();
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

  Future<Map<String, String>> _getAuthHeaders() async {
    final authService = AuthService();
    final token = await authService.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token'
    };
  }

  Future<List<Message>> getMessages({int limit = 100, String? personId}) async {
    if (_inMemory) {
      final list = personId == null
          ? _messages
          : _messages.where((m) => m.id.contains(personId)).toList();
      return list
          .sortedByTimestampDesc()
          .take(limit)
          .toList();
    }
    final db = _ensure();
    final rows = await db.query('messages',
        where: personId != null ? 'person_id = ?' : null,
        whereArgs: personId != null ? [personId] : null,
        orderBy: 'created_at ASC', // Changed to ASC to show oldest first
        limit: limit);
    return rows.map((r) => Message(
      id: r['id'] as String,
      role: _roleFromString(r['role'] as String),
      content: r['content'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    )).toList();
  }

  // Clear all messages (for testing)
  Future<void> clearMessages() async {
    if (_inMemory) {
      _messages.clear();
      return;
    }
    final db = _ensure();
    await db.delete('messages');
  }

  // Get message count
  Future<int> getMessageCount({String? personId}) async {
    if (_inMemory) {
      final list = personId == null
          ? _messages
          : _messages.where((m) => m.id.contains(personId)).toList();
      return list.length;
    }
    final db = _ensure();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages${personId != null ? ' WHERE person_id = ?' : ''}',
      personId != null ? [personId] : null,
    );
    return result.first['count'] as int;
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

  Database _ensure() {
    if (_inMemory) {
      throw StateError('In-memory mode active (web) – no sqlite Database');
    }
    return _db!;
  }
}

extension _SortExt on List<HealthEntry> {
  List<HealthEntry> sortedByTimestampDesc() {
    final copy = List<HealthEntry>.from(this);
    copy.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return copy;
  }
}

extension _MessageSortExt on List<Message> {
  List<Message> sortedByTimestampDesc() {
    final copy = List<Message>.from(this);
    copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy;
  }
}
