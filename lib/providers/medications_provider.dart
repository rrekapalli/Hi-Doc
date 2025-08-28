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
    loading = true; notifyListeners();
  final rows = await db.listMedications(userId: userId, profileId: profileId);
  medications = rows.map((r) => Medication.fromDb(r)).toList();
    loading = false; notifyListeners();
  }

  Future<Medication> create(String name, {String? notes}) async {
    final med = Medication.create(userId: userId, profileId: profileId, name: name, notes: notes);
  await db.createMedication(med.toDb());
    medications.add(med); notifyListeners();
    return med;
  }

  Future<void> update(Medication medication) async {
  await db.updateMedication(medication.toDb());
    final idx = medications.indexWhere((m) => m.id == medication.id);
    if (idx >= 0) medications[idx] = medication; else medications.add(medication);
    notifyListeners();
  }

  Future<void> delete(String id) async {
  await db.deleteMedication(id);
    medications.removeWhere((m) => m.id == id);
    notifyListeners();
  }
}
