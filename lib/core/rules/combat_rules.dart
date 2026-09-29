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
  if (def.tier == EnemyTier.abomination || def.tier == EnemyTier.fatty) {
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

  CombatRules({Random? rng}) : _rng = rng ?? Random();

  // ---- ZONE ATTACK (Zombicide rules) ----

  /// Attack all actors in [targetZoneId].
  /// Hits assigned by targeting priority.
  ZoneCombatResult attackZone(
    GameState state,
    String attackingPlayerId,
    WeaponDefinition weapon,
    String targetZoneId,
  ) {
    final playerIdx = state.players.indexWhere((p) => p.playerId == attackingPlayerId);
    assert(playerIdx != -1);
    final attacker = state.players[playerIdx];

    // Roll dice — add bonus dice from skills.
    final bonusDice = SkillSystem.bonusDice(attacker);
    final totalDice = weapon.dice + bonusDice;
    final rolls = List.generate(totalDice, (_) => _rng.nextInt(6) + 1);
    var hits = rolls.where((r) => r >= weapon.hitValue).length;

    final survivorsInZone = state.players
        .where((p) => !p.isEliminated && p.playerId != attackingPlayerId && p.zoneId == targetZoneId)
        .toList();
    final enemiesInZone = state.enemies
        .where((e) => e.zoneId == targetZoneId)
        .toList();

    var updatedPlayers  = List<PlayerState>.from(state.players);
    var updatedEnemies  = List<EnemyInstance>.from(state.enemies);
    var totalXp         = 0;
    var friendlyFire    = false;
    final eliminatedEnemyIds = <String>[];
    final woundedSurvivorIds = <String>[];
    final logLines = <String>[];

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

      // Abominations are immune to normal weapons.
      if (def.tier == EnemyTier.abomination && !weapon.canHurtAbomination) {
        logLines.add('✗ ${def.name} imune — use arma especial');
        hits--;
        continue;
      }

      final threshold = ignoreArmor ? 1 : def.damageToKill;
      if (weapon.damage < threshold) {
        logLines.add('— ${def.name} absorveu o dano (precisa $threshold dano)');
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

    // Award XP and sync dangerLevel from XP.
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
      attackerId:         attackingPlayerId,
      weaponId:           weapon.id,
      targetZoneId:       targetZoneId,
      rolls:              rolls,
      hits:               hitCount,
      hitValue:           weapon.hitValue,
      eliminatedEnemyIds: eliminatedEnemyIds,
      woundedSurvivorIds: woundedSurvivorIds,
      xpGained:           totalXp,
      friendlyFire:       friendlyFire,
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
      player:      attacker.definitionId,
      weapon:      weapon.name,
      rolls:       rolls,
      hitValue:    weapon.hitValue,
      hits:        hitCount,
      killed:      eliminatedEnemyIds,
      wounded:     woundedSurvivorIds,
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

    final wounded  = _woundPlayer(state.players[idx]);
    final absorbed = wounded.health == state.players[idx].health;
    final log = '${def.name} ataca ${target.definitionId}'
        '${absorbed ? " — bloqueado (Resistência)" : wounded.isEliminated ? " — ELIMINADO" : " → ${wounded.health} HP"}';

    final players = List<PlayerState>.from(state.players)..[idx] = wounded;
    return state.copyWith(
      players:              players,
      eventLog:             [...state.eventLog, log].takeLast(20).toList(),
      lastWoundedPlayerId:  absorbed ? null : target.playerId,
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
    final withPriority = enemies.map((e) {
      final tier = _tierFromId(e.definitionId);
      final def  = _fakeDef(e);
      return (priority: tier.index, enemy: e, def: def);
    }).toList();
    withPriority.sort((a, b) => a.priority.compareTo(b.priority));
    return withPriority.map((e) => (e.enemy, e.def)).toList();
  }

  _TargetPriority _tierFromId(String id) {
    if (id.contains('abomination')) return _TargetPriority.fatAbomination;
    if (id.contains('fatty'))       return _TargetPriority.fatAbomination;
    if (id.contains('runner'))      return _TargetPriority.runner;
    return _TargetPriority.walker;
  }

  EnemyDefinition _fakeDef(EnemyInstance e) {
    final tier = _tierEnum(e.definitionId);
    final dtk = switch (tier) {
      EnemyTier.fatty       => 2,
      EnemyTier.abomination => 999,
      _                     => 1,
    };
    return EnemyDefinition(
      id: e.definitionId, name: e.definitionId,
      type: EnemyType.corruptedDrone,
      tier: tier,
      hp: e.currentHp, damage: 1, actions: 1,
      activationPriority: 1, spriteId: '',
      damageToKill: dtk,
    );
  }

  EnemyTier _tierEnum(String id) {
    if (id.contains('abomination')) return EnemyTier.abomination;
    if (id.contains('fatty'))       return EnemyTier.fatty;
    if (id.contains('runner'))      return EnemyTier.runner;
    return EnemyTier.walker;
  }

  static int _xpFor(EnemyDefinition def) => switch (def.tier) {
    EnemyTier.abomination => _xpPerAbominationKill,
    EnemyTier.fatty       => _xpPerHeavyKill,
    _                     => _xpPerKill,
  };

  static PlayerState _woundPlayer(PlayerState p) {
    if (p.hasArmorVest) return p.copyWith(hasArmorVest: false);
    if (SkillSystem.hasResistance(p) && !p.resistanceUsedThisTurn) {
      return p.copyWith(resistanceUsedThisTurn: true);
    }
    final newHealth = p.health - 1;
    return p.copyWith(
      health:      newHealth,
      isEliminated: newHealth <= 0,
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
