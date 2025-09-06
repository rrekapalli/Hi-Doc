import 'package:flutter/foundation.dart';
import '../models/activity.dart';
import '../services/activities_service.dart';
import 'chat_provider.dart';

class ActivitiesProvider with ChangeNotifier {
  final ActivitiesService _service = ActivitiesService();
  final ChatProvider chatProvider;

  List<Activity> _all = [];
  bool _loading = false;
  String? _error;

  ActivitiesProvider({required this.chatProvider}) {
  // Listen for profile changes to auto-filter.
  chatProvider.addListener(_onProfileChanged);
  }

  List<Activity> get activities {
  final pid = chatProvider.currentProfileId;
  if (pid == null) return _all;
  return _all.where((a) => a.profileId == pid).toList();
  }
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _service.listActivities(limit: 500);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Activity?> addActivity(Activity draft) async {
    try {
      final created = await _service.createActivity(draft);
      if (created != null) {
        _all.add(created);
        notifyListeners();
      }
      return created;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  void _onProfileChanged() {
    // Just notify listeners so UI re-filters list
    notifyListeners();
  }

  @override
  void dispose() {
  chatProvider.removeListener(_onProfileChanged);
    super.dispose();
  }
}
