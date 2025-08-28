import 'package:flutter/material.dart';
import '../../models/medication_models.dart';
import 'medication_wizard_screen.dart';

/// Deprecated legacy schedule screen replaced by unified MedicationWizardScreen.
class MedicationScheduleScreen extends StatelessWidget {
  final Map<String, dynamic> medication; // legacy map
  const MedicationScheduleScreen({super.key, required this.medication});
  @override
  Widget build(BuildContext context) {
    return MedicationWizardScreen(
      editMedication: Medication(
        id: medication['id'] as String,
        userId: 'prototype-user-12345',
        profileId: 'default-profile',
        name: medication['name'] as String? ?? '',
        notes: medication['dosage'] as String?,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
      for (final time in _times) {
        final reminderData = {
          'user_id': userId,
          'medication_id': widget.medication['id'],
          'title': widget.medication['name'],
          'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          'message': 'Time to take ${widget.medication['name']} ${widget.medication['dosage'] ?? ''}',
          'repeat': _isDaily ? 'daily' : 'weekly',
          'days': _isDaily ? null : _selectedDays
              .asMap()
              .entries
              .where((e) => e.value)
              .map((e) => (e.key + 1).toString())
              .join(','),
          'active': 1,
        };
        
        debugPrint('Inserting reminder: $reminderData');
        await db.insertReminder(reminderData);
      }

      // Update notifications
      await db.updateMedicationReminders(widget.medication['id'] as String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule saved and notifications set')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save schedule: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: devTitle(context, 'medication_schedule_screen.dart', const Text('Schedule Medication')),
        actions: [
          TextButton(
            // Deprecated: medication_schedule_screen.dart removed in favor of medication_wizard_screen.dart
            // File intentionally left nearly empty to avoid broken imports during transition. Will be deleted.
          ),
