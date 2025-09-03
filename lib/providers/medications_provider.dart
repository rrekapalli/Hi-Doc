import 'package:flutter/foundation.dart';
import '../services/database_service.dart';
import '../models/medication_models.dart';

class MedicationsProvider extends ChangeNotifier {
  final DatabaseService db;
  final String userId;
  final String profileId;
  List<Medication> medications = [];
  bool loading = false;

  MedicationsProvider({required this.db, required this.userId, required this.profileId});

  Future<void> load() async {
    loading = true;
    notifyListeners();
    final rows = await db.listMedications(userId: userId, profileId: profileId);
    medications = rows.map((r) => Medication.fromDb(r)).toList();
    if (kDebugMode) {
      try {
        final all = await db.rawQuery('SELECT user_id, profile_id, COUNT(*) c FROM medications GROUP BY user_id, profile_id');
        debugPrint('[MedicationsProvider.load] requested userId=$userId profileId=$profileId -> ${medications.length} meds. All groups: $all');
      } catch (_) {}
    }
  loading = false;
  notifyListeners();
  }

  Future<Medication> create(String name, {String? notes}) async {
    var med = Medication.create(userId: userId, profileId: profileId, name: name, notes: notes);
    final data = med.toDb();
    final newId = await db.createMedication(data);
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
  notifyListeners();
    return med;
  }

  Future<void> update(Medication medication) async {
    await db.updateMedication(medication.toDb());
    final idx = medications.indexWhere((m) => m.id == medication.id);
    if (idx >= 0) {
      medications[idx] = medication;
    } else {
      medications.add(medication);
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await db.deleteMedication(id);
    medications.removeWhere((m) => m.id == id);
    notifyListeners();
  }
}
