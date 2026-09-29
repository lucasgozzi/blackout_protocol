import '../models/mission.dart';
import '../models/tutorial_hint.dart';

class TutorialSystem {
  const TutorialSystem._();

  /// Returns the first unshown hint for [trigger], or null if none.
  /// [shownIds] is the set of hint ids already displayed this session.
  static TutorialHint? check(
    MissionDefinition mission,
    String trigger,
    Set<String> shownIds,
  ) {
    for (final raw in mission.tutorialHints) {
      final hint = TutorialHint.fromJson(raw);
      if (hint.trigger == trigger && !shownIds.contains(hint.id)) return hint;
    }
    return null;
  }
}
