import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';

class EditMedicationScreen extends StatefulWidget {
  final Map<String, dynamic> medication;
  
  const EditMedicationScreen({
    super.key,
    required this.medication,
  });

  @override
  State<EditMedicationScreen> createState() => _EditMedicationScreenState();
}

// Deprecated legacy editor retained as stub to avoid import errors. Redirect users to MedicationWizardScreen.
import 'medication_wizard_screen.dart';

class EditMedicationScreen extends StatelessWidget {
  final Map<String, dynamic> medication;
  const EditMedicationScreen({super.key, required this.medication});
  @override
  Widget build(BuildContext context) {
    return MedicationWizardScreen(
      editMedication: Medication(
        id: medication['id'] as String,
  userId: 'prototype-user',
        profileId: 'default-profile',
        name: medication['name'] as String? ?? '',
        notes: medication['dosage'] as String?,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _frequencyController,
              decoration: const InputDecoration(
                labelText: 'Frequency per Day',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            Text(
              'Schedule Type',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'fixed',
                  label: Text('Fixed'),
                ),
                ButtonSegment<String>(
                  value: 'as_needed',
                  label: Text('As Needed'),
                ),
                ButtonSegment<String>(
                  value: 'continuous',
                  label: Text('Continuous'),
                ),
              ],
              selected: {_scheduleType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _scheduleType = newSelection.first;
                });
              },
            ),
            if (_scheduleType == 'fixed') ...[
              const SizedBox(height: 24),
              Text(
                'Duration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('From'),
                      subtitle: Text(
                        _fromDate != null 
                            ? '${_fromDate!.year}-${_fromDate!.month.toString().padLeft(2, '0')}-${_fromDate!.day.toString().padLeft(2, '0')}'
                            : 'Not set',
                      ),
                      onTap: () => _selectDate(context, true),
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      title: const Text('To'),
                      subtitle: Text(
                        _toDate != null 
                            ? '${_toDate!.year}-${_toDate!.month.toString().padLeft(2, '0')}-${_toDate!.day.toString().padLeft(2, '0')}'
                            : 'Not set',
                      ),
                      onTap: () => _selectDate(context, false),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
