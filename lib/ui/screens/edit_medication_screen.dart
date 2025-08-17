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

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _doseController;
  late TextEditingController _doseUnitController;
  late TextEditingController _frequencyController;
  late String _scheduleType;
  DateTime? _fromDate;
  DateTime? _toDate;
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.medication['name'] as String);
    _doseController = TextEditingController(text: (widget.medication['dose']?.toString() ?? ''));
    _doseUnitController = TextEditingController(text: widget.medication['dose_unit'] as String?);
    _frequencyController = TextEditingController(
      text: (widget.medication['frequency_per_day']?.toString() ?? '')
    );
    _scheduleType = widget.medication['schedule_type'] as String? ?? 'fixed';
    
    if (widget.medication['from_date'] != null) {
      _fromDate = DateTime.fromMillisecondsSinceEpoch(widget.medication['from_date'] as int);
    }
    if (widget.medication['to_date'] != null) {
      _toDate = DateTime.fromMillisecondsSinceEpoch(widget.medication['to_date'] as int);
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _doseUnitController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    if (_scheduleType != 'fixed') return;
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate 
          ? _fromDate ?? DateTime.now()
          : _toDate ?? ((_fromDate ?? DateTime.now()).add(const Duration(days: 7))),
      firstDate: isFromDate ? DateTime(2020) : (_fromDate ?? DateTime(2020)),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          // If to date is before from date, update it
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = _fromDate!.add(const Duration(days: 7));
          }
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final db = context.read<DatabaseService>();
      final updatedMedication = {
        'id': widget.medication['id'],
        'name': _nameController.text,
        'dose': double.tryParse(_doseController.text),
        'doseUnit': _doseUnitController.text,
        'frequencyPerDay': int.tryParse(_frequencyController.text),
        'scheduleType': _scheduleType,
        'fromDate': _scheduleType == 'fixed' ? _fromDate : null,
        'toDate': _scheduleType == 'fixed' ? _toDate : null,
      };

      await db.updateMedication(updatedMedication);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medication updated successfully')),
        );
        Navigator.of(context).pop(true); // true indicates successful update
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update medication: $e'),
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
        title: const Text('Edit Medication'),
        actions: [
          TextButton(
            onPressed: _saveMedication,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Medication Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter medication name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _doseController,
                    decoration: const InputDecoration(
                      labelText: 'Dose',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _doseUnitController,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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
