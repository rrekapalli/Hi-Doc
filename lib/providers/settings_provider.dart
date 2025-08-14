import 'package:flutter/foundation.dart';

class SettingsProvider extends ChangeNotifier {
  bool enableLocalModel = false; // future (B)
  bool enableHeuristics = true;  // (A)
  bool enableBackendAI = true;   // allow turning off remote

  void toggleLocalModel(bool v) { enableLocalModel = v; notifyListeners(); }
  void toggleHeuristics(bool v) { enableHeuristics = v; notifyListeners(); }
  void toggleBackendAI(bool v) { enableBackendAI = v; notifyListeners(); }
}
