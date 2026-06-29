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
  final int worldX;
  final int worldY;

  SpawnStep({
    required this.zoneId,
    required this.zoneName,
    required this.enemyId,
    required this.enemyName,
    required this.tier,
    required this.count,
    required this.worldX,
    required this.worldY,
  });
}

/// Single enemy move — kept internally but collapsed into EnemyGroupMoveStep.
class EnemyMoveStep extends EnemyTurnStep {
  final String instanceId;
  final String definitionId;
  final String enemyName;
  final EnemyTier tier;
  final int fromX;
  final int fromY;
  final int toX;
  final int toY;

  EnemyMoveStep({
    required this.instanceId,
    required this.definitionId,
    required this.enemyName,
    required this.tier,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });
}

/// All moves for enemies of the same type, played simultaneously.
class EnemyGroupMoveStep extends EnemyTurnStep {
  final String definitionId;
  final String enemyName;
  final EnemyTier tier;
  final List<EnemyMoveStep> moves; // one per enemy in the group

  /// World-space centroid of all destination positions — camera target.
  int get centerX => moves.isEmpty ? 0
      : moves.map((m) => m.toX).reduce((a, b) => a + b) ~/ moves.length;
  int get centerY => moves.isEmpty ? 0
      : moves.map((m) => m.toY).reduce((a, b) => a + b) ~/ moves.length;

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
  final int worldX;
  final int worldY;
  final String targetPlayerId;
  final String targetName;
  final bool playerWounded;
  final bool playerEliminated;

  EnemyAttackStep({
    required this.instanceId,
    required this.definitionId,
    required this.enemyName,
    required this.tier,
    required this.worldX,
    required this.worldY,
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
