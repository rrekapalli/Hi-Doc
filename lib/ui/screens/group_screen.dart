import 'package:flutter/material.dart';
import 'user_settings_screen.dart';
import '../common/hi_doc_app_bar.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HiDocAppBar(
        pageTitle: 'Group',
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserSettingsScreen()),
            ),
          )
        ],
      ),
      body: const Center(child: Text('Group management (TODO)')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }
}
