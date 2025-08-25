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
    // Listen for conversation changes to auto-filter.
    chatProvider.addListener(_onConversationChanged);
  }

  List<Activity> get activities {
    final cid = chatProvider.currentConversationId;
    if (cid == null) return _all;
    return _all.where((a) => a.conversationId == cid).toList();
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

  void _onConversationChanged() {
    // Just notify listeners so UI re-filters list
    notifyListeners();
  }

  @override
  void dispose() {
    chatProvider.removeListener(_onConversationChanged);
    super.dispose();
  }
}
