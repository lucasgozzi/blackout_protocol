import '../models/enemy.dart';

/// A single unit of cinematics for the enemy phase.
/// The UI iterates through these sequentially, panning the camera and
/// displaying appropriate overlays.
sealed class EnemyTurnStep {}

/// Camera pans to a spawn zone, the spawn card is revealed, then enemies appear.
class SpawnStep extends EnemyTurnStep {
  final String zoneId;
  final String zoneName;
  final String enemyId;
  final String enemyName;
  final EnemyTier tier;
  final int count;

  SpawnStep({
    required this.zoneId,
    required this.zoneName,
    required this.enemyId,
    required this.enemyName,
    required this.tier,
    required this.count,
  });
}

/// Single enemy move — kept internally but collapsed into EnemyGroupMoveStep.
class EnemyMoveStep extends EnemyTurnStep {
  final String instanceId;
  final String definitionId;
  final String enemyName;
  final EnemyTier tier;
  final String fromZoneId;
  final String toZoneId;

  EnemyMoveStep({
    required this.instanceId,
    required this.definitionId,
    required this.enemyName,
    required this.tier,
    required this.fromZoneId,
    required this.toZoneId,
  });
}

/// All moves for enemies of the same type, played simultaneously.
class EnemyGroupMoveStep extends EnemyTurnStep {
  final String definitionId;
  final String enemyName;
  final EnemyTier tier;
  final List<EnemyMoveStep> moves;

  /// Most common destination zone for camera targeting.
  String get toZoneId {
    if (moves.isEmpty) return '';
    final counts = <String, int>{};
    for (final m in moves) counts[m.toZoneId] = (counts[m.toZoneId] ?? 0) + 1;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  EnemyGroupMoveStep({
    required this.definitionId,
    required this.enemyName,
    required this.tier,
    required this.moves,
  });
}

/// Camera pans to an enemy that is attacking a survivor.
class EnemyAttackStep extends EnemyTurnStep {
  final String instanceId;
  final String definitionId;
  final String enemyName;
  final EnemyTier tier;
  final String zoneId;
  final String targetPlayerId;
  final String targetName;
  final bool playerWounded;
  final bool playerEliminated;

  EnemyAttackStep({
    required this.instanceId,
    required this.definitionId,
    required this.enemyName,
    required this.tier,
    required this.zoneId,
    required this.targetPlayerId,
    required this.targetName,
    required this.playerWounded,
    this.playerEliminated = false,
  });
}

/// A completed script for one full enemy phase.
class EnemyTurnScript {
  final List<EnemyTurnStep> steps;
  const EnemyTurnScript(this.steps);

  bool get isEmpty => steps.isEmpty;
}
