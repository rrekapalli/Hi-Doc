import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../providers/selected_profile_provider.dart';
import '../../providers/chat_provider.dart';
import 'contact_search_dialog.dart';

class ProfileSwitchDialog extends StatefulWidget {
  const ProfileSwitchDialog({super.key});

  @override
  State<ProfileSwitchDialog> createState() => _ProfileSwitchDialogState();
}

class _ProfileSwitchDialogState extends State<ProfileSwitchDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _profiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = context.read<DatabaseService>();
      final raw = await db.getProfiles();
      setState(() {
        _profiles = raw;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _switch(String profileId) async {
    final selected = context.read<SelectedProfileProvider>();
    final chat = context.read<ChatProvider>();
    selected.setSelectedProfile(profileId);
    chat.setCurrentProfile(profileId);
    await chat.loadMessages(profileId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editProfile(Map<String, dynamic> profile) async {
    // Requirement: Edit acts like creating a new profile group
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ContactSearchDialog(),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final current = context.watch<SelectedProfileProvider>().selectedProfileId;
    return Dialog(
      child: SizedBox(
        width: 420,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Switch Profiles',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load profiles', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry'))
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: _profiles.isEmpty
                      ? const Center(child: Text('No profiles found'))
                      : ListView.separated(
                          itemCount: _profiles.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final p = _profiles[i];
                            final id = p['id'] as String? ?? '';
                            final title = p['title'] as String? ?? 'Unnamed';
                            final type = p['type'] as String? ?? 'direct';
                            final memberNames = p['member_names'] as String?;
                            final isActive = id == current;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('Active', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                              subtitle: memberNames != null && memberNames.isNotEmpty
                                  ? Text(memberNames, maxLines: 1, overflow: TextOverflow.ellipsis)
                                  : Text(type),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Switch',
                                    icon: const Icon(Icons.swap_horiz),
                                    onPressed: () => _switch(id),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit (create new group)',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editProfile(p),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => const ContactSearchDialog(),
                    );
                    if (mounted) _load();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New Profile'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
