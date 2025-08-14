import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable heuristics parsing'),
            subtitle: const Text('Use fast regex extraction before AI'),
            value: settings.enableHeuristics,
            onChanged: settings.toggleHeuristics,
          ),
          SwitchListTile(
            title: const Text('Enable local model (device only)'),
            subtitle: const Text('Attempt on-device LLaMA parsing'),
            value: settings.enableLocalModel,
            onChanged: settings.toggleLocalModel,
          ),
          SwitchListTile(
            title: const Text('Enable backend AI'),
            subtitle: const Text('Call server if local / heuristics insufficient'),
            value: settings.enableBackendAI,
            onChanged: settings.toggleBackendAI,
          ),
        ],
      ),
    );
  }
}
