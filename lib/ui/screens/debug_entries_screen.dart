import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../models/health_entry.dart';
import '../common/hi_doc_app_bar.dart';

class DebugEntriesScreen extends StatefulWidget {
  const DebugEntriesScreen({super.key});

  @override
  State<DebugEntriesScreen> createState() => _DebugEntriesScreenState();
}

class _DebugEntriesScreenState extends State<DebugEntriesScreen> {
  late Future<List<HealthEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final db = context.read<DatabaseService>();
    _entriesFuture = db.listAllEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HiDocAppBar(
        pageTitle: 'Debug Entries',
      ),
      body: FutureBuilder<List<HealthEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? [];
          if (entries.isEmpty) return const Center(child: Text('No entries'));
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (c, i) {
              final e = entries[i];
              String title;
              if (e.vital != null) {
                final v = e.vital!;
                if (v.vitalType == VitalType.bloodPressure) {
                  title =
                      'BP ${v.systolic?.toStringAsFixed(0)}/${v.diastolic?.toStringAsFixed(0)} ${v.unit ?? ''}'
                          .trim();
                } else {
                  title =
                      '${v.vitalType.name}: ${v.value?.toStringAsFixed(1) ?? ''} ${v.unit ?? ''}'
                          .trim();
                }
              } else if (e.note != null) {
                title = 'Note: ${e.note}';
              } else if (e.medication != null) {
                title = 'Medication: ${e.medication!.name}';
              } else if (e.labResult != null) {
                title = 'Lab: ${e.labResult!.sourceFilePath}';
              } else {
                title = e.type.name;
              }
              return ListTile(
                title: Text(title),
                subtitle: Text(e.timestamp.toIso8601String()),
              );
            },
          );
        },
      ),
    );
  }
}
