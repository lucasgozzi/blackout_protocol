import 'package:shared_preferences/shared_preferences.dart';

class ProgressRepository {
  static const _key = 'completed_missions';

  Future<Set<String>> loadCompletedMissions() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).toSet();
  }

  Future<void> markMissionCompleted(String missionId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_key) ?? []).toSet()..add(missionId);
    await prefs.setStringList(_key, current.toList());
  }
}
