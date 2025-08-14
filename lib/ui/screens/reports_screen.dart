import 'package:flutter/material.dart';
import 'user_settings_screen.dart';
import '../common/hi_doc_app_bar.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Reports',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          )
        ],
      ),
      body: const Center(child: Text('Reports list & upload (TODO)')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.file_upload),
      ),
    );
  }
}
