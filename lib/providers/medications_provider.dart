import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../models/medication_models.dart';
import '../utils/performance_monitor.dart';

class MedicationsProvider extends ChangeNotifier {
  final DatabaseService db;
  final String userId;
  final String profileId;
  List<Medication> medications = [];
  bool loading = false;
  DateTime? _lastLoadTime;

  // Cache to prevent unnecessary database calls
  static const Duration _cacheTimeout = Duration(minutes: 5);

  MedicationsProvider({
    required this.db,
    required this.userId,
    required this.profileId,
  });

  /// Load medications with caching and performance monitoring
  Future<void> load({bool forceRefresh = false}) async {
    // Check cache validity
    if (!forceRefresh &&
        _lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!) < _cacheTimeout) {
      return;
    }

    if (loading) return; // Prevent concurrent loads

    loading = true;
    notifyListeners();

    try {
      final rows = await PerformanceMonitor.timeAsync(
        'medications_load',
        () => db.listMedications(userId: userId, profileId: profileId),
      );

      medications = rows.map((r) => Medication.fromDb(r)).toList();
      _lastLoadTime = DateTime.now();

      if (kDebugMode) {
        try {
          final all = await db.rawQuery(
            'SELECT user_id, profile_id, COUNT(*) c FROM medications GROUP BY user_id, profile_id',
          );
          debugPrint(
            '[MedicationsProvider.load] requested userId=$userId profileId=$profileId -> ${medications.length} meds. All groups: $all',
          );
        } catch (_) {}
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Medication> create(String name, {String? notes}) async {
    var med = Medication.create(
      userId: userId,
      profileId: profileId,
      name: name,
      notes: notes,
    );
    final data = med.toDb();

    final newId = await PerformanceMonitor.timeAsync(
      'medication_create',
      () => db.createMedication(data),
    );

    if (newId != med.id) {
      // Rebuild with backend id
      med = Medication(
        id: newId,
        userId: med.userId,
        profileId: med.profileId,
        name: med.name,
        notes: med.notes,
        medicationUrl: med.medicationUrl,
        createdAt: med.createdAt,
        updatedAt: med.updatedAt,
      );
    }

    medications.add(med);
    _invalidateCache();
    notifyListeners();
    return med;
  }

  Future<void> update(Medication medication) async {
    await PerformanceMonitor.timeAsync(
      'medication_update',
      () => db.updateMedication(medication.toDb()),
    );

    final idx = medications.indexWhere((m) => m.id == medication.id);
    if (idx >= 0) {
      medications[idx] = medication;
    } else {
      medications.add(medication);
    }
    _invalidateCache();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await PerformanceMonitor.timeAsync(
      'medication_delete',
      () => db.deleteMedication(id),
    );

    medications.removeWhere((m) => m.id == id);
    _invalidateCache();
    notifyListeners();
  }

  /// Invalidate cache to force refresh on next load
  void _invalidateCache() {
    _lastLoadTime = null;
  }

  /// Check if data needs refresh
  bool get needsRefresh {
    return _lastLoadTime == null ||
        DateTime.now().difference(_lastLoadTime!) >= _cacheTimeout;
  }

  @override
  void dispose() {
    medications.clear();
    _invalidateCache();
    super.dispose();
  }
}
