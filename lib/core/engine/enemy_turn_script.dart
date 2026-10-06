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

  Map<String, dynamic> toJson() => {
    'steps': steps.map(_stepToJson).toList(),
  };

  factory EnemyTurnScript.fromJson(Map<String, dynamic> json) {
    final steps = (json['steps'] as List)
        .map((s) => _stepFromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    return EnemyTurnScript(steps);
  }

  static Map<String, dynamic> _stepToJson(EnemyTurnStep step) => switch (step) {
    SpawnStep s => {
      'type': 'spawn', 'zoneId': s.zoneId, 'zoneName': s.zoneName,
      'enemyId': s.enemyId, 'enemyName': s.enemyName,
      'tier': s.tier.name, 'count': s.count,
    },
    EnemyGroupMoveStep s => {
      'type': 'groupMove', 'definitionId': s.definitionId,
      'enemyName': s.enemyName, 'tier': s.tier.name,
      'moves': s.moves.map((m) => {
        'instanceId': m.instanceId, 'definitionId': m.definitionId,
        'enemyName': m.enemyName, 'tier': m.tier.name,
        'fromZoneId': m.fromZoneId, 'toZoneId': m.toZoneId,
      }).toList(),
    },
    EnemyMoveStep s => {
      'type': 'enemyMove', 'instanceId': s.instanceId,
      'definitionId': s.definitionId, 'enemyName': s.enemyName,
      'tier': s.tier.name, 'fromZoneId': s.fromZoneId, 'toZoneId': s.toZoneId,
    },
    EnemyAttackStep s => {
      'type': 'attack', 'instanceId': s.instanceId,
      'definitionId': s.definitionId, 'enemyName': s.enemyName,
      'tier': s.tier.name, 'zoneId': s.zoneId,
      'targetPlayerId': s.targetPlayerId, 'targetName': s.targetName,
      'playerWounded': s.playerWounded, 'playerEliminated': s.playerEliminated,
    },
  };

  static EnemyTurnStep _stepFromJson(Map<String, dynamic> m) {
    EnemyTier tier() => EnemyTier.values.firstWhere(
        (t) => t.name == m['tier'], orElse: () => EnemyTier.walker);
    return switch (m['type'] as String) {
      'spawn' => SpawnStep(
          zoneId: m['zoneId'] as String, zoneName: m['zoneName'] as String,
          enemyId: m['enemyId'] as String, enemyName: m['enemyName'] as String,
          tier: tier(), count: m['count'] as int),
      'groupMove' => EnemyGroupMoveStep(
          definitionId: m['definitionId'] as String,
          enemyName: m['enemyName'] as String, tier: tier(),
          moves: (m['moves'] as List).map((mv) {
            final mm = Map<String, dynamic>.from(mv as Map);
            final t = EnemyTier.values.firstWhere(
                (t) => t.name == mm['tier'], orElse: () => EnemyTier.walker);
            return EnemyMoveStep(
              instanceId: mm['instanceId'] as String,
              definitionId: mm['definitionId'] as String,
              enemyName: mm['enemyName'] as String, tier: t,
              fromZoneId: mm['fromZoneId'] as String,
              toZoneId: mm['toZoneId'] as String,
            );
          }).toList()),
      'enemyMove' => EnemyMoveStep(
          instanceId: m['instanceId'] as String,
          definitionId: m['definitionId'] as String,
          enemyName: m['enemyName'] as String, tier: tier(),
          fromZoneId: m['fromZoneId'] as String, toZoneId: m['toZoneId'] as String),
      'attack' => EnemyAttackStep(
          instanceId: m['instanceId'] as String,
          definitionId: m['definitionId'] as String,
          enemyName: m['enemyName'] as String, tier: tier(),
          zoneId: m['zoneId'] as String,
          targetPlayerId: m['targetPlayerId'] as String,
          targetName: m['targetName'] as String,
          playerWounded: m['playerWounded'] as bool,
          playerEliminated: m['playerEliminated'] as bool? ?? false),
      _ => throw ArgumentError('Unknown step type: ${m["type"]}'),
    };
  }
}
