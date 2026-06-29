import '../models/game_state.dart';
import '../models/mission.dart';

class AlertSystem {
  /// Increments alert level and fires any events at the new threshold.
  /// Returns updated GameState and the list of events that triggered.
  ({GameState state, List<AlertEvent> triggered}) increment(
    GameState state,
    MissionDefinition mission, {
    int amount = 1,
  }) {
    final newLevel = (state.alertLevel + amount).clamp(0, mission.maxAlertLevel);
    final triggered = _eventsAt(newLevel, mission, state.alertLevel);

    final log = 'Alert level: ${state.alertLevel} → $newLevel'
        '${triggered.isNotEmpty ? " ⚠ ${triggered.map((e) => e.description).join(", ")}" : ""}';

    final newState = state.copyWith(
      alertLevel: newLevel,
      outcome: newLevel >= mission.maxAlertLevel ? GameOutcome.defeat : state.outcome,
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );

    return (state: newState, triggered: triggered);
  }

  /// Returns events whose trigger level falls in (previousLevel, newLevel].
  List<AlertEvent> _eventsAt(
    int newLevel,
    MissionDefinition mission,
    int previousLevel,
  ) =>
      mission.alertEvents
          .where((e) =>
              e.triggerAlertLevel > previousLevel &&
              e.triggerAlertLevel <= newLevel)
          .toList();

  /// Whether the current alert level triggers a specific action.
  static bool isAtOrAbove(GameState state, int threshold) =>
      state.alertLevel >= threshold;
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
