import 'package:flutter/foundation.dart';

/// Holds the globally selected profile id so any screen can read it.
class SelectedProfileProvider extends ChangeNotifier {
  String _selectedProfileId = 'default-profile';

  String get selectedProfileId => _selectedProfileId;

  void setSelectedProfile(String id) {
    if (_selectedProfileId == id) return;
    _selectedProfileId = id;
    notifyListeners();
  }
}
