import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';

class UserSettingsScreen extends StatelessWidget {
  const UserSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Account'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Profile', icon: Icon(Icons.person_outline)),
            Tab(text: 'Settings', icon: Icon(Icons.tune_outlined)),
          ]),
        ),
        body: const TabBarView(children: [
          _ProfileTab(),
          _SettingsTab(),
        ]),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          if (user != null) ...[
            CircleAvatar(
              radius: 40,
              backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
              child: user.photoURL == null ? const Icon(Icons.person, size: 48) : null,
            ),
            const SizedBox(height: 16),
            Text(user.displayName ?? 'Unnamed User', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(user.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => auth.signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ] else ...[
            const Icon(Icons.person_off, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Not signed in', textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return ListView(
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
    );
  }
}
