import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_settings_screen.dart';
import '../common/hi_doc_app_bar.dart';
import '../../providers/activities_provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/activity.dart';

class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});
  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      // Trigger load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<ActivitiesProvider>().load();
      });
      _initialLoadDone = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activitiesProvider = context.watch<ActivitiesProvider>();
    final chat = context.watch<ChatProvider>();
    final activities = activitiesProvider.activities;

    return Scaffold(
      appBar: const HiDocAppBar(
        pageTitle: 'Activities',
      ),
      body: RefreshIndicator(
        onRefresh: () async => activitiesProvider.load(),
        child: Builder(
          builder: (context) {
            if (activitiesProvider.isLoading && activities.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (activitiesProvider.error != null && activities.isEmpty) {
              return Center(child: Text('Failed to load activities\n${activitiesProvider.error}', textAlign: TextAlign.center));
            }
            if (activities.isEmpty) {
              return Center(
        child: Text(chat.currentProfileId == null
          ? 'No activities recorded yet.'
          : 'No activities for this profile.'),
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: activities.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final a = activities[index];
                return _ActivityTile(activity: a);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Placeholder for adding manual activity entry in future
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual activity entry not implemented yet')));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Activity activity;
  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (activity.durationMinutes != null) {
      subtitleParts.add('${activity.durationMinutes} min');
    }
    if (activity.distanceKm != null) {
      subtitleParts.add('${activity.distanceKm!.toStringAsFixed(2)} km');
    }
    if (activity.caloriesBurned != null) {
      subtitleParts.add('${activity.caloriesBurned!.toStringAsFixed(0)} kcal');
    }
    if (activity.intensity != null) {
      subtitleParts.add(activity.intensity!);
    }
    final ts = TimeOfDay.fromDateTime(activity.timestamp);
    final dateStr = '${activity.timestamp.year}-${activity.timestamp.month.toString().padLeft(2,'0')}-${activity.timestamp.day.toString().padLeft(2,'0')} ${ts.format(context)}';

    return ListTile(
      leading: const Icon(Icons.directions_run),
      title: Text(activity.name),
      subtitle: Text([
        if (subtitleParts.isNotEmpty) subtitleParts.join(' · '),
        dateStr,
      ].join('\n')),
      isThreeLine: true,
  trailing: Text(activity.profileId, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

