import '../models/game_state.dart';
import '../models/player.dart';
import '../models/skill.dart';

class SkillSystem {
  /// Returns effective actions per turn for a player (3 + extras from skills).
  static int actionsPerTurn(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    final extra  = skills
        .where((s) => s.effect.type == SkillEffectType.extraAction)
        .fold(0, (sum, s) => sum + s.effect.value);
    return 3 + extra;
  }

  /// Returns effective movement range (base + extras from skills).
  static int movementRange(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    final extra  = skills
        .where((s) => s.effect.type == SkillEffectType.extraMovement)
        .fold(0, (sum, s) => sum + s.effect.value);
    return player.movementRange + extra;
  }

  /// Bonus dice granted by skills for a given attack.
  static int bonusDice(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    return skills
        .where((s) => s.effect.type == SkillEffectType.extraDice)
        .fold(0, (sum, s) => sum + s.effect.value);
  }

  /// Whether the player ignores enemy armor.
  static bool ignoresArmor(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    return skills.any((s) => s.effect.type == SkillEffectType.ignoreArmor);
  }

  /// Whether opening a door costs no action for this player.
  static bool freeOpenDoor(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    return skills.any((s) => s.effect.type == SkillEffectType.freeOpenDoor);
  }

  /// Whether searching heals a danger level for this player.
  static bool healOnSearch(PlayerState player) {
    final skills = unlockedSkillsFor(player.definitionId, player.dangerLevel);
    return skills.any((s) => s.effect.type == SkillEffectType.healOnSearch);
  }

  /// Check for level-up when XP changes. Adds newly-unlocked skill IDs and
  /// updates dangerLevel. Returns updated PlayerState + newly unlocked skills.
  static ({PlayerState player, List<SkillDefinition> newSkills}) applyXp(
    PlayerState player,
    int newXp,
  ) {
    final oldLevel = player.dangerLevel;
    final newLevel = _levelForXp(newXp);
    final gained   = newlyUnlockedSkills(player.definitionId, oldLevel, newLevel);

    final updated = player.copyWith(
      xp: newXp,
      dangerLevel: newLevel,
      unlockedAbilities: [
        ...player.unlockedAbilities,
        ...gained.map((s) => s.id),
      ],
    );
    return (player: updated, newSkills: gained);
  }

  /// Apply heal-on-search: move danger level down one step.
  static PlayerState applyHeal(PlayerState player) {
    final healed = switch (player.dangerLevel) {
      DangerLevel.red    => DangerLevel.orange,
      DangerLevel.orange => DangerLevel.yellow,
      DangerLevel.yellow => DangerLevel.blue,
      DangerLevel.blue   => DangerLevel.blue,
    };
    return player.copyWith(dangerLevel: healed);
  }

  /// Emit level-up events to the game log.
  static GameState applyLevelUpLog(
    GameState state,
    PlayerState player,
    List<SkillDefinition> newSkills,
  ) {
    if (newSkills.isEmpty) return state;
    final logs = newSkills.map((s) =>
        '⬆ ${player.definitionId} desbloqueou: ${s.name} — ${s.description}').toList();
    return state.copyWith(
      eventLog: [...state.eventLog, ...logs].takeLast(20).toList(),
    );
  }

  static DangerLevel _levelForXp(int xp) {
    if (xp >= 43) return DangerLevel.red;
    if (xp >= 19) return DangerLevel.orange;
    if (xp >= 7)  return DangerLevel.yellow;
    return DangerLevel.blue;
  }
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
