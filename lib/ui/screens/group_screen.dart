import 'package:flutter/material.dart';
import 'user_settings_screen.dart';
import '../common/hi_doc_app_bar.dart';

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HiDocAppBar(
        pageTitle: 'Activities',
      ),
      body: const Center(child: Text('Activity management (TODO)')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
