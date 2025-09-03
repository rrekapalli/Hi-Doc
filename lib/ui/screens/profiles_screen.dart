// Simplified Messages view: show only the default profile chat (no left-side listing panel)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import './profile_detail_screen.dart';
import '../common/hi_doc_app_bar.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final String _activeProfileId = 'default-profile';

  @override
  void initState() {
    super.initState();
    // Ensure chat provider targets default profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      if (chat.currentProfileId != _activeProfileId) {
        chat.setCurrentProfile(_activeProfileId);
        chat.loadMessages(_activeProfileId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const HiDocAppBar(pageTitle: 'Messages'),
      body: ProfileDetailScreen(
        profileId: _activeProfileId,
        title: 'Me',
        profileType: 'direct',
        embedded: true, // we already provide scaffold/app bar here
      ),
    );
  }
}
