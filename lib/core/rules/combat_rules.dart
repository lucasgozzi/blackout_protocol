import 'dart:math';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/weapon.dart';
import '../engine/mission_logger.dart';
import 'skill_system.dart';

final _log = MissionLogger.instance;

// ---- Target priority (Zombicide order) ----
// Ranged: Survivors first (friendly fire), then Walkers, then Fatties/Abominations, then Runners
// Melee:  Player freely distributes hits among enemies in same zone

enum _TargetPriority { survivor, walker, fatAbomination, runner }

_TargetPriority _priorityOf(EnemyDefinition def) {
  if (def.tier == EnemyTier.abomination || def.tier == EnemyTier.heavy) {
    return _TargetPriority.fatAbomination;
  }
  if (def.tier == EnemyTier.runner) return _TargetPriority.runner;
  return _TargetPriority.walker;
}

class ZoneCombatResult {
  final GameState state;
  final ZoneCombatLog log;

  const ZoneCombatResult({required this.state, required this.log});
}

class CombatRules {
  static const int _xpPerKill = 1;
  static const int _xpPerHeavyKill = 3;
  static const int _xpPerAbominationKill = 5;

  final Random _rng;
  // Set by TurnManager after map load so zone radius scales with tile size.
  int tilePixelSize = 200;

  CombatRules({Random? rng}) : _rng = rng ?? Random();

  // ---- ZONE ATTACK (Zombicide rules) ----

  /// Attack a zone at (targetX, targetY).
  /// Weapon determines range, dice, hitValue, damage.
  /// Hits assigned by targeting priority.
  ZoneCombatResult attackZone(
    GameState state,
    String attackingPlayerId,
    WeaponDefinition weapon,
    int targetX,
    int targetY,
  ) {
    final playerIdx = state.players.indexWhere((p) => p.playerId == attackingPlayerId);
    assert(playerIdx != -1);
    final attacker = state.players[playerIdx];

    // Roll dice — add bonus dice from skills.
    final bonusDice = SkillSystem.bonusDice(attacker);
    final totalDice = weapon.dice + bonusDice;
    final rolls = List.generate(totalDice, (_) => _rng.nextInt(6) + 1);
    var hits = rolls.where((r) => r >= weapon.hitValue).length;

    // Collect actors in target zone.
    // Use half-tile radius so actors in adjacent zones aren't accidentally included.
    final zoneRadius = (tilePixelSize * 0.6).round();
    bool inZone(int ax, int ay) =>
        (ax - targetX).abs() <= zoneRadius && (ay - targetY).abs() <= zoneRadius;

    final survivorsInZone = state.players
        .where((p) => !p.isEliminated && p.playerId != attackingPlayerId && inZone(p.x, p.y))
        .toList();
    final enemiesInZone = state.enemies
        .where((e) => inZone(e.x, e.y))
        .toList();

    var updatedPlayers  = List<PlayerState>.from(state.players);
    var updatedEnemies  = List<EnemyInstance>.from(state.enemies);
    var totalXp = 0;
    var friendlyFire = false;
    final eliminatedEnemyIds  = <String>[];
    final woundedSurvivorIds  = <String>[];
    final logLines = <String>[];

    // Zombicide rule: weapon.damage must be >= enemy.damageToKill to kill it.
    // Each kill costs exactly 1 hit. Hits on enemies the weapon can't kill are wasted.
    // Melee = no friendly fire. Ranged = misses hit survivors first.

    final ignoreArmor = SkillSystem.ignoresArmor(attacker);

    if (!weapon.isMelee) {
      // Friendly fire: misses automatically hit survivors in zone.
      final misses = rolls.where((r) => r < weapon.hitValue).length;
      if (misses > 0 && survivorsInZone.isNotEmpty) {
        friendlyFire = true;
        for (var m = 0; m < misses && m < survivorsInZone.length; m++) {
          final survivor = survivorsInZone[m];
          final idx = updatedPlayers.indexWhere((p) => p.playerId == survivor.playerId);
          if (idx == -1) continue;
          updatedPlayers[idx] = _woundPlayer(updatedPlayers[idx]);
          woundedSurvivorIds.add(survivor.playerId);
          logLines.add('⚠ Fogo amigo: ${survivor.definitionId}');
        }
      }

      // Hits: survivors first, then enemies by priority.
      for (final survivor in survivorsInZone) {
        if (hits <= 0) break;
        final idx = updatedPlayers.indexWhere((p) => p.playerId == survivor.playerId);
        if (idx == -1) continue;
        updatedPlayers[idx] = _woundPlayer(updatedPlayers[idx]);
        woundedSurvivorIds.add(survivor.playerId);
        logLines.add('⚠ Acerto em ${survivor.definitionId}');
        hits--;
      }
    }

    // Apply hits to enemies (melee and ranged share this logic).
    final sorted = _sortEnemiesByPriority(enemiesInZone, state);
    for (final entry in sorted) {
      if (hits <= 0) break;
      final (enemy, def) = entry;
      final threshold = ignoreArmor ? 1 : def.damageToKill;

      if (weapon.damage < threshold) {
        // Weapon too weak — hit absorbed, enemy survives, hit consumed (wasted).
        logLines.add('— ${def.name} absorveu o dano (precisa ${threshold} dano)');
        hits--;
        continue;
      }

      // 1 hit = 1 kill when weapon.damage >= damageToKill.
      updatedEnemies.removeWhere((e) => e.instanceId == enemy.instanceId);
      eliminatedEnemyIds.add(enemy.instanceId);
      totalXp += _xpFor(def);
      logLines.add('✓ ${def.name} eliminado');
      hits--;
    }

    // Award XP and sync dangerLevel from XP (always derived, never stored separately).
    final newXp = attacker.xp + totalXp;
    final updatedAttacker = updatedPlayers[playerIdx].copyWith(
      actionsRemaining: attacker.actionsRemaining - 1,
      xp: newXp,
      dangerLevel: _levelForXp(newXp),
    );
    updatedPlayers[playerIdx] = updatedAttacker;

    final rollSummary = rolls.join(',');
    final hitCount = rolls.where((r) => r >= weapon.hitValue).length;
    logLines.insert(0, '${weapon.name} → [$rollSummary] $hitCount acertos');

    final combatLog = ZoneCombatLog(
      attackerId: attackingPlayerId,
      weaponId: weapon.id,
      targetX: targetX,
      targetY: targetY,
      rolls: rolls,
      hits: hitCount,
      eliminatedEnemyIds: eliminatedEnemyIds,
      woundedSurvivorIds: woundedSurvivorIds,
      xpGained: totalXp,
      friendlyFire: friendlyFire,
    );

    var newState = state.copyWith(
      players:       updatedPlayers,
      enemies:       updatedEnemies,
      lastCombatLog: combatLog,
      eventLog: [...state.eventLog, ...logLines].takeLast(20).toList(),
    );

    // Consume grenade if single-use.
    if (weapon.isConsumable) {
      newState = _consumeItem(newState, attackingPlayerId, weapon.id);
    }

    _log.playerAttack(
      player: attacker.definitionId,
      weapon: weapon.name,
      rolls: rolls,
      hitValue: weapon.hitValue,
      hits: hitCount,
      killed: eliminatedEnemyIds,
      wounded: woundedSurvivorIds,
      friendlyFire: friendlyFire,
    );

    return ZoneCombatResult(state: newState, log: combatLog);
  }

  // ---- ENEMY ATTACK ----

  GameState enemyAttackPlayer(
    GameState state,
    EnemyInstance enemy,
    EnemyDefinition def,
    PlayerState target,
  ) {
    final idx = state.players.indexWhere((p) => p.playerId == target.playerId);
    if (idx == -1) return state;

    final wounded = _woundPlayer(state.players[idx]);
    final log = '${def.name} ataca ${target.definitionId}'
        '${wounded.isEliminated ? " — ELIMINADO" : " → ${wounded.dangerLevel.name}"}';

    final players = List<PlayerState>.from(state.players)..[idx] = wounded;
    return state.copyWith(
      players: players,
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
      lastWoundedPlayerId: target.playerId,
    );
  }

  // ---- Private helpers ----

  static DangerLevel _levelForXp(int xp) {
    if (xp >= 43) return DangerLevel.red;
    if (xp >= 19) return DangerLevel.orange;
    if (xp >= 7)  return DangerLevel.yellow;
    return DangerLevel.blue;
  }

  List<(EnemyInstance, EnemyDefinition)> _sortEnemiesByPriority(
    List<EnemyInstance> enemies,
    GameState state,
  ) {
    // We can't look up EnemyDefinition here without catalog.
    // Approximate: sort by tier string in definitionId.
    final withPriority = enemies.map((e) {
      final tier = _tierFromId(e.definitionId);
      final def = _fakeDef(e);
      return (priority: tier.index, enemy: e, def: def);
    }).toList();
    withPriority.sort((a, b) => a.priority.compareTo(b.priority));
    return withPriority.map((e) => (e.enemy, e.def)).toList();
  }

  _TargetPriority _tierFromId(String id) {
    if (id.contains('abomination')) return _TargetPriority.fatAbomination;
    if (id.contains('heavy'))       return _TargetPriority.fatAbomination;
    if (id.contains('runner'))      return _TargetPriority.runner;
    return _TargetPriority.walker;
  }

  // Minimal EnemyDefinition built from instance id for internal logic.
  EnemyDefinition _fakeDef(EnemyInstance e) => EnemyDefinition(
    id: e.definitionId, name: e.definitionId,
    type: EnemyType.corruptedDrone,
    tier: _tierEnum(e.definitionId),
    hp: e.currentHp, damage: 1, actions: 1,
    activationPriority: 1, spriteId: '',
  );

  EnemyTier _tierEnum(String id) {
    if (id.contains('abomination')) return EnemyTier.abomination;
    if (id.contains('heavy'))       return EnemyTier.heavy;
    if (id.contains('runner'))      return EnemyTier.runner;
    return EnemyTier.walker;
  }

  static int _armorOf(EnemyDefinition def) {
    if (def.specialAbilities.contains('armor_2')) return 2;
    if (def.specialAbilities.contains('armor_1')) return 1;
    return 0;
  }

  static int _xpFor(EnemyDefinition def) => switch (def.tier) {
    EnemyTier.abomination => _xpPerAbominationKill,
    EnemyTier.heavy       => _xpPerHeavyKill,
    _                     => _xpPerKill,
  };

  static PlayerState _woundPlayer(PlayerState p) {
    // Armor vest absorbs one wound.
    if (p.hasArmorVest) return p.copyWith(hasArmorVest: false);

    // Zombicide-style: 2 hits to eliminate (blue → yellow → dead).
    final next = switch (p.dangerLevel) {
      DangerLevel.blue   => DangerLevel.yellow,
      DangerLevel.yellow => DangerLevel.red,
      DangerLevel.orange => DangerLevel.red,
      DangerLevel.red    => DangerLevel.red,
    };
    return p.copyWith(
      dangerLevel: next,
      isEliminated: p.dangerLevel == DangerLevel.yellow ||
                    p.dangerLevel == DangerLevel.orange  ||
                    p.dangerLevel == DangerLevel.red,
    );
  }

  static GameState _consumeItem(GameState state, String playerId, String itemId) {
    final idx = state.players.indexWhere((p) => p.playerId == playerId);
    if (idx == -1) return state;
    final p = state.players[idx];

    PlayerState updated;
    if (p.equippedLeft == itemId) {
      updated = p.copyWith(equippedLeft: null);
    } else if (p.equippedRight == itemId) {
      updated = p.copyWith(equippedRight: null);
    } else {
      final bp = List<String>.from(p.backpack)..remove(itemId);
      updated = p.copyWith(backpack: bp);
    }

    final players = List<PlayerState>.from(state.players)..[idx] = updated;
    return state.copyWith(players: players);
  }
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
