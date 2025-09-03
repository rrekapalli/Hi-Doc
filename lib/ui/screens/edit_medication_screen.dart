// Clean replacement: the old EditMedicationScreen was corrupted. We now forward to MedicationWizardScreen.
import 'package:flutter/material.dart';
import '../../models/medication_models.dart';
import 'medication_wizard_screen.dart';

class EditMedicationScreen extends StatelessWidget {
  final Map<String, dynamic> medication;
  const EditMedicationScreen({super.key, required this.medication});

  @override
  Widget build(BuildContext context) {
    return MedicationWizardScreen(
      editMedication: Medication(
        id: medication['id'] as String? ?? '',
        userId: medication['userId'] as String? ?? 'prototype-user',
        profileId: medication['profileId'] as String? ?? 'default-profile',
        name: medication['name'] as String? ?? '',
        notes: medication['notes'] as String?,
        createdAt: medication['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
