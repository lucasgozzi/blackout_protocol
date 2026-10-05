import '../models/game_state.dart';
import '../models/mission.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/weapon.dart';
import '../engine/enemy_turn_script.dart';
import '../engine/mission_logger.dart';
import 'alert_system.dart';
import 'combat_rules.dart';
import 'noise_system.dart';
import 'search_system.dart';
import 'skill_system.dart';
import 'spawn_deck.dart';
import 'spawn_system.dart';

final _log = MissionLogger.instance;

class TurnManager {
  final AlertSystem _alertSystem;
  final CombatRules _combatRules;
  final SpawnSystem _spawnSystem;
  final EnemyCatalogLookup _catalog;
  SearchSystem? searchSystem;
  SpawnDeck?   spawnDeck;
  MissionDefinition? _mission;
  // Zone graph — set when session starts.
  dynamic _mapData; // MapData from data/map_loader.dart (dynamic to avoid circular import)

  TurnManager({
    required AlertSystem alertSystem,
    required CombatRules combatRules,
    required SpawnSystem spawnSystem,
    required EnemyCatalogLookup catalog,
  })  : _alertSystem = alertSystem,
        _combatRules = combatRules,
        _spawnSystem = spawnSystem,
        _catalog = catalog;

  void setMission(MissionDefinition mission) => _mission = mission;
  void setMapData(dynamic mapData) => _mapData = mapData;

  AlertSystem get alertSystem => _alertSystem;
  CombatRules get combatRules => _combatRules;
  SpawnSystem get spawnSystem => _spawnSystem;

  // ---- OPEN DOOR (1 action) ----

  bool canOpenDoor(PlayerState player) => player.actionsRemaining > 0;

  GameState openDoor(GameState state, String playerId, String fromZoneId, String toZoneId) {
    final idx    = _playerIdx(state, playerId);
    final player = state.players[idx];
    if (!canOpenDoor(player)) return state;

    final key        = '$fromZoneId|$toZoneId';
    final alreadyOpen = state.openDoors.contains(key) ||
        state.openDoors.contains('$toZoneId|$fromZoneId');
    if (alreadyOpen) return state;

    final free           = SkillSystem.freeOpenDoor(player);
    final updatedPlayer  = free
        ? player
        : player.copyWith(actionsRemaining: player.actionsRemaining - 1);
    _log.playerOpenDoor(player.definitionId, fromZoneId, toZoneId);
    final log = '${player.definitionId} abriu porta → $toZoneId${free ? " (grátis)" : ""}';

    return state.copyWith(
      players:  List<PlayerState>.from(state.players)..[idx] = updatedPlayer,
      openDoors: [...state.openDoors, key],
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- MOVE (1 action, moves to target zone) ----

  bool canMove(PlayerState player) {
    final maxZones = SkillSystem.movementRange(player);
    return player.actionsRemaining > 0 && player.zonesMovedThisTurn < maxZones;
  }

  GameState movePlayer(GameState state, String playerId, String zoneId) {
    final idx    = _playerIdx(state, playerId);
    final player = state.players[idx];
    assert(canMove(player), 'Player has no movement remaining');

    _log.playerMove(player.definitionId, player.zoneId, zoneId);

    final maxZones = SkillSystem.movementRange(player);
    final updated  = player.copyWith(
      zoneId:             zoneId,
      actionsRemaining:   player.actionsRemaining - 1,
      zonesMovedThisTurn: maxZones,
    );
    final logMsg  = '${player.definitionId} → $zoneId';
    final moved   = _updatePlayer(state, idx, updated).copyWith(
      eventLog: [...state.eventLog, logMsg].takeLast(20).toList(),
    );
    return _checkReachObjectives(moved);
  }

  /// After each player move, auto-complete any "reach" type objectives whose
  /// zone condition is now satisfied.
  GameState _checkReachObjectives(GameState state) {
    if (_mapData == null) return state;
    var current = state;

    for (var i = 0; i < current.objectives.length; i++) {
      final o = current.objectives[i];
      if (o.isCompleted || o.type != ObjectiveType.reach) continue;

      final targetTag = o.params['targetTileTag'] as String?;
      if (targetTag == null) continue;

      final requireAll = (o.params['requireAllPlayers'] as bool?) ?? false;
      final alive = current.players.where((p) => !p.isEliminated).toList();

      // ignore: avoid_print
      print('[REACH] obj=${o.id} requireAll=$requireAll alive=${alive.length}');
      for (final p in alive) {
        final atTarget = _playerInTaggedZone(p.zoneId, targetTag);
        // ignore: avoid_print
        print('[REACH]   ${p.definitionId} zone=${p.zoneId} atTarget=$atTarget');
      }

      final met = requireAll
          ? alive.every((p) => _playerInTaggedZone(p.zoneId, targetTag))
          : alive.any((p) => _playerInTaggedZone(p.zoneId, targetTag));

      if (!met) continue;

      final log  = '🎯 ${o.description} — concluído!';
      final objs = List.of(current.objectives)..[i] = o.copyWith(isCompleted: true);
      current = current.copyWith(
        objectives: objs,
        eventLog:   [...current.eventLog, log].takeLast(20).toList(),
      );
      current = _checkVictory(current);
    }

    return current;
  }

  bool _playerInTaggedZone(String zoneId, String tag) {
    if (_mapData == null || zoneId.isEmpty) return false;
    try {
      final found = (_mapData as dynamic).findZone(zoneId);
      return found != null && (found.zone.tags as List).contains(tag);
    } catch (_) {
      return false;
    }
  }

  // ---- ATTACK ZONE (1 action) ----

  ZoneCombatResult attackZone(
    GameState state,
    String playerId,
    WeaponDefinition weapon,
    String targetZoneId,
  ) {
    var result = _combatRules.attackZone(state, playerId, weapon, targetZoneId);

    if (weapon.isNoisy) {
      result = ZoneCombatResult(
        state: NoiseSystem.addNoise(result.state, targetZoneId, 1),
        log:   result.log,
      );
    }

    final checkedState = _checkEliminateObjectives(result.state);
    return ZoneCombatResult(state: checkedState, log: result.log);
  }

  /// Marks any `eliminate` objective as completed when all enemies are gone.
  GameState _checkEliminateObjectives(GameState state) {
    final hasEliminate = state.objectives.any(
      (o) => !o.isCompleted && o.type == ObjectiveType.eliminate,
    );
    if (!hasEliminate || state.enemies.isNotEmpty) return state;

    var current = state;
    for (var i = 0; i < current.objectives.length; i++) {
      final o = current.objectives[i];
      if (o.isCompleted || o.type != ObjectiveType.eliminate) continue;
      final objs = List.of(current.objectives)..[i] = o.copyWith(isCompleted: true);
      final log  = '🎯 ${o.description} — concluído!';
      current = current.copyWith(
        objectives: objs,
        eventLog:   [...current.eventLog, log].takeLast(20).toList(),
      );
    }
    return _checkVictory(current);
  }

  // ---- SEARCH (1 action) ----

  ({GameState state, String? pendingLootId}) search(
    GameState state,
    String playerId,
    String? objectiveId,
  ) {
    final idx    = _playerIdx(state, playerId);
    final player = state.players[idx];
    if (player.actionsRemaining <= 0) return (state: state, pendingLootId: null);

    if (objectiveId != null && objectiveId.isNotEmpty) {
      final objIdx = state.objectives.indexWhere((o) => o.id == objectiveId);
      if (objIdx != -1 && !state.objectives[objIdx].isCompleted) {
        final obj            = state.objectives[objIdx];
        final requiredCount  = (obj.params['requiredCount'] as num?)?.toInt() ?? 1;
        final currentCount   = (obj.params['currentCount']  as num?)?.toInt() ?? 0;
        final newCount       = currentCount + 1;
        final isNowDone      = newCount >= requiredCount;

        // Track which zone contributed so _syncItems can deplete it individually.
        final collectedZones = List<String>.from(
            (obj.params['collectedZones'] as List?)?.cast<String>() ?? [])
          ..add(player.zoneId);

        final newParams = Map<String, dynamic>.from(obj.params)
          ..['currentCount']   = newCount
          ..['collectedZones'] = collectedZones;

        final updatedObj = List.of(state.objectives)
          ..[objIdx] = obj.copyWith(isCompleted: isNowDone, params: newParams);
        final updatedPlayer = _addItemToInventory(
          player.copyWith(actionsRemaining: player.actionsRemaining - 1),
          objectiveId,
        );
        final log = '${player.definitionId} coletou: ${obj.description} ($newCount/$requiredCount)';
        final newState = state.copyWith(
          objectives: updatedObj,
          players:    List.of(state.players)..[idx] = updatedPlayer,
          eventLog:   [...state.eventLog, log].takeLast(20).toList(),
        );
        return (state: _checkVictory(newState), pendingLootId: null);
      }
    }

    final loot     = searchSystem?.draw();
    final isUseful = loot != null && !loot.isNothing;
    var afterAction = player.copyWith(actionsRemaining: player.actionsRemaining - 1);

    if (SkillSystem.healOnSearch(player) && player.dangerLevel != DangerLevel.blue) {
      afterAction = SkillSystem.applyHeal(afterAction);
    }

    _log.playerSearch(player.definitionId, isUseful ? loot!.id : null);
    final log = isUseful
        ? '${player.definitionId} encontrou: ${loot!.name}'
        : '${player.definitionId} buscou — nada encontrado';

    return (
      state: state.copyWith(
        players:  List.of(state.players)..[idx] = afterAction,
        eventLog: [...state.eventLog, log].takeLast(20).toList(),
      ),
      pendingLootId: isUseful ? loot!.id : null,
    );
  }

  GameState placeLoot(GameState state, String playerId, String itemId, String slot) {
    final idx    = _playerIdx(state, playerId);
    final player = state.players[idx];

    PlayerState updated;
    switch (slot) {
      case 'left':
        final displaced = player.equippedLeft;
        final bp = List<String>.from(player.backpack);
        if (displaced != null && displaced != itemId) bp.add(displaced);
        updated = player.copyWith(equippedLeft: itemId, backpack: bp);
      case 'right':
        final displaced = player.equippedRight;
        final bp = List<String>.from(player.backpack);
        if (displaced != null && displaced != itemId) bp.add(displaced);
        updated = player.copyWith(equippedRight: itemId, backpack: bp);
      case 'backpack':
        if (player.backpack.length >= 3) return state;
        updated = player.copyWith(backpack: [...player.backpack, itemId]);
      default:
        return state;
    }

    return state.copyWith(
      players: List.of(state.players)..[idx] = updated,
    );
  }

  // ---- TRADE ITEM (1 action, same zone) ----

  bool canTrade(PlayerState from, PlayerState to) =>
      from.actionsRemaining > 0 &&
      !from.isEliminated &&
      !to.isEliminated &&
      from.zoneId == to.zoneId;

  GameState tradeItem(
    GameState state,
    String fromPlayerId,
    String toPlayerId,
    String itemId,
  ) {
    final fromIdx = _playerIdx(state, fromPlayerId);
    final toIdx   = _playerIdx(state, toPlayerId);
    final from    = state.players[fromIdx];
    final to      = state.players[toIdx];

    if (!canTrade(from, to)) return state;
    if (to.inventoryFull) return state;

    PlayerState updatedFrom;
    if (from.equippedLeft == itemId) {
      updatedFrom = from.copyWith(equippedLeft: null, actionsRemaining: from.actionsRemaining - 1);
    } else if (from.equippedRight == itemId) {
      updatedFrom = from.copyWith(equippedRight: null, actionsRemaining: from.actionsRemaining - 1);
    } else if (from.backpack.contains(itemId)) {
      final bp = List<String>.from(from.backpack)..remove(itemId);
      updatedFrom = from.copyWith(backpack: bp, actionsRemaining: from.actionsRemaining - 1);
    } else {
      return state;
    }

    PlayerState updatedTo;
    if (to.equippedLeft == null) {
      updatedTo = to.copyWith(equippedLeft: itemId);
    } else if (to.equippedRight == null) {
      updatedTo = to.copyWith(equippedRight: itemId);
    } else {
      updatedTo = to.copyWith(backpack: [...to.backpack, itemId]);
    }

    final log     = '${from.definitionId} deu $itemId para ${to.definitionId}';
    final players = List<PlayerState>.from(state.players)
      ..[fromIdx] = updatedFrom
      ..[toIdx]   = updatedTo;

    return state.copyWith(
      players:  players,
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- PLACE TRAP (1 action) ----

  bool canPlaceTrap(PlayerState player) =>
      player.actionsRemaining > 0 &&
      !player.isEliminated &&
      SkillSystem.electricTrapDamage(player) > 0;

  GameState placeTrap(GameState state, String playerId) {
    final idx    = _playerIdx(state, playerId);
    final player = state.players[idx];
    if (!canPlaceTrap(player)) return state;

    final key     = player.zoneId;
    final damage  = SkillSystem.electricTrapDamage(player);
    final updated = player.copyWith(actionsRemaining: player.actionsRemaining - 1);
    final log     = '⚡ ${player.definitionId} instalou armadilha em $key';

    return state.copyWith(
      players:  List<PlayerState>.from(state.players)..[idx] = updated,
      traps:    {...state.traps, key: damage},
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- HEAL ALLY (1 action, same zone) ----

  bool canHealAlly(PlayerState healer, PlayerState target) =>
      healer.actionsRemaining > 0 &&
      !healer.isEliminated &&
      !target.isEliminated &&
      healer.playerId != target.playerId &&
      healer.zoneId == target.zoneId &&
      target.health < 2 &&
      SkillSystem.canHealAlly(healer);

  GameState healAlly(GameState state, String healerId, String targetId) {
    final healerIdx = _playerIdx(state, healerId);
    final targetIdx = _playerIdx(state, targetId);
    final healer    = state.players[healerIdx];
    final target    = state.players[targetIdx];

    if (!canHealAlly(healer, target)) return state;

    final updatedTarget = SkillSystem.applyHeal(target);
    final updatedHealer = healer.copyWith(actionsRemaining: healer.actionsRemaining - 1);
    final log = '💉 ${healer.definitionId} curou ${target.definitionId} → ${updatedTarget.health} HP';
    final players = List<PlayerState>.from(state.players)
      ..[healerIdx] = updatedHealer
      ..[targetIdx] = updatedTarget;

    return state.copyWith(
      players:  players,
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- AREA HEAL ALLY (1 action, heals all allies in same zone) ----

  bool canAreaHealAlly(PlayerState healer, List<PlayerState> allPlayers) =>
      healer.actionsRemaining > 0 &&
      !healer.isEliminated &&
      SkillSystem.canAreaHealAlly(healer) &&
      allPlayers.any((p) =>
          p.playerId != healer.playerId &&
          !p.isEliminated &&
          p.zoneId == healer.zoneId &&
          p.health < 2);

  GameState areaHealAlly(GameState state, String healerId) {
    final healerIdx = _playerIdx(state, healerId);
    final healer    = state.players[healerIdx];

    if (!canAreaHealAlly(healer, state.players)) return state;

    var players    = List<PlayerState>.from(state.players);
    final healed   = <String>[];
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      if (p.playerId == healerId || p.isEliminated) continue;
      if (p.zoneId != healer.zoneId) continue;
      if (p.health < 2) {
        players[i] = SkillSystem.applyHeal(p);
        healed.add(p.definitionId);
      }
    }
    players[healerIdx] = healer.copyWith(actionsRemaining: healer.actionsRemaining - 1);

    final log = '💉 ${healer.definitionId} Pulso Vital curou: ${healed.join(', ')}';
    return state.copyWith(
      players:  players,
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- INTERACT (delegates to search) ----

  ({GameState state, bool success}) interact(
    GameState state,
    String playerId,
    String objectiveId,
  ) {
    final result = search(state, playerId, objectiveId);
    return (state: result.state, success: result.pendingLootId != null);
  }

  // ---- END PLAYER TURN ----

  ({GameState state, EnemyTurnScript script, bool enemyPhaseRan}) endPlayerTurn(GameState state) {
    final alive = state.players.where((p) => !p.isEliminated).toList();
    if (alive.isEmpty) {
      _log.enemyPhaseStart();
      final r = _beginEnemyPhase(state);
      return (state: r.state, script: r.script, enemyPhaseRan: true);
    }

    final currentAliveIdx = alive.indexWhere((p) => p.playerId == state.activePlayerId);
    final nextAliveIdx    = (currentAliveIdx + 1) % alive.length;
    final next            = alive[nextAliveIdx];

    final allActed = nextAliveIdx == 0;
    if (allActed) {
      for (final p in alive) {
        _log.playerState(p.definitionId, p.dangerLevel.name, p.xp,
            p.actionsRemaining, p.zonesMovedThisTurn, SkillSystem.movementRange(p));
      }
      _log.enemyPhaseStart();
      final r = _beginEnemyPhase(state);
      return (state: r.state, script: r.script, enemyPhaseRan: true);
    }
    _log.endPlayerTurn(
        state.players.firstWhere((p) => p.playerId == state.activePlayerId).definitionId,
        state.players.firstWhere((p) => p.playerId == state.activePlayerId).actionsRemaining);
    return (state: state.copyWith(activePlayerId: next.playerId), script: EnemyTurnScript([]), enemyPhaseRan: false);
  }

  // ---- ENEMY PHASE ----

  ({GameState state, EnemyTurnScript script}) _beginEnemyPhase(GameState state) {
    final reset = state.enemies.map((e) => e.copyWith(activated: false)).toList();
    return _runEnemyPhase(state.copyWith(phase: GamePhase.enemyTurn, enemies: reset));
  }

  ({GameState state, EnemyTurnScript script}) _runEnemyPhase(GameState state) {
    final rawSteps = <EnemyTurnStep>[];
    final ordered  = List<EnemyInstance>.from(state.enemies)
      ..sort((a, b) {
        final pa = _catalog.getById(a.definitionId).activationPriority;
        final pb = _catalog.getById(b.definitionId).activationPriority;
        return pa.compareTo(pb);
      });

    var current = state;
    for (final enemy in ordered) {
      if (current.outcome != GameOutcome.none) break;
      final result = _activateEnemy(current, enemy);
      current = result.state;
      rawSteps.addAll(result.steps);
    }

    final alertResult = _beginAlertPhase(current);
    final steps       = _groupMoveSteps(rawSteps);
    steps.addAll(alertResult.spawnSteps);

    return (state: alertResult.state, script: EnemyTurnScript(steps));
  }

  List<EnemyTurnStep> _groupMoveSteps(List<EnemyTurnStep> raw) {
    final movesByDef = <String, List<EnemyMoveStep>>{};
    for (final s in raw) {
      if (s is EnemyMoveStep) {
        (movesByDef[s.definitionId] ??= []).add(s);
      }
    }

    final emitted = <String>{};
    final result  = <EnemyTurnStep>[];
    for (final s in raw) {
      if (s is EnemyMoveStep) {
        if (emitted.contains(s.definitionId)) continue;
        emitted.add(s.definitionId);
        result.add(EnemyGroupMoveStep(
          definitionId: s.definitionId,
          enemyName:    s.enemyName,
          tier:         s.tier,
          moves:        movesByDef[s.definitionId]!,
        ));
      } else {
        result.add(s);
      }
    }
    return result;
  }

  ({GameState state, List<EnemyTurnStep> steps}) _activateEnemy(
      GameState state, EnemyInstance enemy) {
    final def     = _catalog.getById(enemy.definitionId);
    final actions = def.actions;

    var current      = state;
    var currentEnemy = enemy;
    final steps      = <EnemyTurnStep>[];

    for (var a = 0; a < actions; a++) {
      final fresh = current.enemies.firstWhere(
        (e) => e.instanceId == currentEnemy.instanceId,
        orElse: () => currentEnemy,
      );
      currentEnemy = fresh;

      // 1. Survivor in same zone → attack.
      final survivor = _survivorInSameZone(currentEnemy, current);
      if (survivor != null) {
        final dangerBefore = survivor.dangerLevel;
        current = _combatRules.enemyAttackPlayer(current, currentEnemy, def, survivor);
        final afterState = current.players
            .firstWhere((p) => p.playerId == survivor.playerId,
                orElse: () => survivor);
        _log.enemyAttack(
          enemy:       def.name,
          instanceId:  currentEnemy.instanceId,
          target:      survivor.definitionId,
          dangerBefore: dangerBefore.name,
          dangerAfter: afterState.dangerLevel.name,
          eliminated:  afterState.isEliminated,
        );
        steps.add(EnemyAttackStep(
          instanceId:       currentEnemy.instanceId,
          definitionId:     def.id,
          enemyName:        def.name,
          tier:             def.tier,
          zoneId:           currentEnemy.zoneId,
          targetPlayerId:   survivor.playerId,
          targetName:       survivor.definitionId,
          playerWounded:    afterState.dangerLevel != dangerBefore,
          playerEliminated: afterState.isEliminated,
        ));
        continue;
      }

      // 2. Move one zone toward target.
      final targetZoneId = _chooseTargetZoneId(current, currentEnemy);
      if (targetZoneId == null) continue;
      final nextZoneId = _nextZoneToward(currentEnemy, targetZoneId, current);
      if (nextZoneId == null) continue;

      _log.enemyMove(def.name, currentEnemy.instanceId, currentEnemy.zoneId, nextZoneId);
      steps.add(EnemyMoveStep(
        instanceId:   currentEnemy.instanceId,
        definitionId: def.id,
        enemyName:    def.name,
        tier:         def.tier,
        fromZoneId:   currentEnemy.zoneId,
        toZoneId:     nextZoneId,
      ));

      var moved   = currentEnemy.copyWith(zoneId: nextZoneId, activated: true);
      final enemies = List<EnemyInstance>.from(current.enemies);
      final idx     = enemies.indexWhere((e) => e.instanceId == currentEnemy.instanceId);

      // Check if the destination has an active trap.
      final trapDamage = current.traps[nextZoneId];
      var updatedTraps = current.traps;
      var trapLog      = '';
      if (trapDamage != null) {
        moved        = moved.copyWith(currentHp: moved.currentHp - trapDamage);
        updatedTraps = Map<String, int>.from(current.traps)..remove(nextZoneId);
        trapLog      = ' | ⚡ armadilha causou $trapDamage de dano';
      }

      if (moved.currentHp <= 0) {
        enemies.removeWhere((e) => e.instanceId == moved.instanceId);
      } else {
        if (idx != -1) enemies[idx] = moved;
      }

      final log = '${def.name} move → $nextZoneId$trapLog';
      current = current.copyWith(
        enemies:  enemies,
        traps:    updatedTraps,
        eventLog: [...current.eventLog, log].takeLast(20).toList(),
      );
    }
    return (state: current, steps: steps);
  }

  PlayerState? _survivorInSameZone(EnemyInstance enemy, GameState state) {
    if (enemy.zoneId.isEmpty) return null;
    try {
      return state.players.firstWhere(
          (p) => !p.isEliminated && p.zoneId == enemy.zoneId);
    } catch (_) {
      return null;
    }
  }

  String? _chooseTargetZoneId(GameState state, EnemyInstance enemy) {
    final alive = state.players.where((p) => !p.isEliminated).toList();
    if (alive.isEmpty) return null;

    final enemyZoneId = enemy.zoneId;
    if (enemyZoneId.isEmpty) {
      return alive.first.zoneId.isEmpty ? null : alive.first.zoneId;
    }

    // 1. Survivors in visible zones (current + adjacent).
    final visibleZones = _visibleZones(enemyZoneId);
    final survivorZoneCounts = <String, int>{};
    for (final p in alive) {
      if (visibleZones.contains(p.zoneId)) {
        survivorZoneCounts[p.zoneId] = (survivorZoneCounts[p.zoneId] ?? 0) + 1;
      }
    }
    if (survivorZoneCounts.isNotEmpty) {
      return survivorZoneCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    // 2. Noisiest visible zone.
    String? noisiest;
    int maxNoise = 0;
    for (final zoneId in visibleZones) {
      final noise = state.noiseTokens[zoneId] ?? 0;
      if (noise > maxNoise) {
        maxNoise = noise;
        noisiest = zoneId;
      }
    }
    if (noisiest != null) return noisiest;

    // 3. Noisiest zone on whole map.
    if (state.noiseTokens.isNotEmpty) {
      return state.noiseTokens.entries
          .reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    // 4. Any alive player's zone.
    final target = alive.firstOrNull;
    return (target != null && target.zoneId.isNotEmpty) ? target.zoneId : null;
  }

  String? _nextZoneToward(EnemyInstance enemy, String targetZoneId, GameState state) {
    final fromZoneId = enemy.zoneId;
    if (fromZoneId.isEmpty || fromZoneId == targetZoneId) return null;

    if (_mapData == null) return null;

    // BFS to find shortest path.
    final prev  = <String, String?>{fromZoneId: null};
    final queue = [fromZoneId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == targetZoneId) break;
      for (final adj in _adjacentZoneIds(current)) {
        if (!prev.containsKey(adj)) {
          prev[adj] = current;
          queue.add(adj);
        }
      }
    }

    if (!prev.containsKey(targetZoneId)) return null;

    String? step = targetZoneId;
    while (prev[step] != fromZoneId && prev[step] != null) {
      step = prev[step];
    }
    return step;
  }

  Set<String> _visibleZones(String fromZoneId) {
    final result = <String>{fromZoneId};
    result.addAll(_adjacentZoneIds(fromZoneId));
    return result;
  }

  List<String> _adjacentZoneIds(String zoneId) {
    if (_mapData == null) return [];
    try {
      return (_mapData.adjacentZones(zoneId, ignoreDoors: true) as Iterable)
          .map<String>((e) => e.zone.id as String)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---- ALERT PHASE ----

  ({GameState state, List<SpawnStep> spawnSteps}) _beginAlertPhase(GameState state) {
    final phaseState = state.copyWith(phase: GamePhase.alertPhase);
    final mission    = _mission;
    if (mission == null) return (state: phaseState, spawnSteps: []);

    final alertResult = _alertSystem.increment(phaseState, mission);
    var current = alertResult.state;
    for (final event in alertResult.triggered) {
      current = _spawnSystem.spawnFromEvent(current, mission, event);
    }

    final deck = spawnDeck;
    final List<SpawnStep> spawnSteps;
    if (deck != null && (mission.spawnPoints.isNotEmpty || current.spawnZones.isNotEmpty)) {
      final result = _spawnFromDeck(current, mission, deck);
      current    = result.state;
      spawnSteps = result.spawnSteps;
    } else {
      current    = _spawnSystem.spawnForAlertLevel(current, mission);
      spawnSteps = [];
    }

    return (state: current, spawnSteps: spawnSteps);
  }

  ({GameState state, List<SpawnStep> spawnSteps}) _spawnFromDeck(
    GameState state,
    MissionDefinition mission,
    SpawnDeck deck,
  ) {
    final spawnIds = state.spawnZones.isNotEmpty
        ? state.spawnZones
        : mission.spawnPoints.map((s) => s.id).toList();

    var current              = state;
    final spawnSteps         = <SpawnStep>[];
    final enemyCap = state.players.length * 3 + 2;

    for (final zoneId in spawnIds) {
      if (current.outcome != GameOutcome.none) break;
      if (current.enemies.length >= enemyCap) break;

      final card = deck.draw();
      if (card.type == SpawnCardType.abomination && state.alertLevel < 7) continue;

      final def = _catalog.getById(card.enemyId);

      _log.spawn(zoneId, def.name, card.count);
      current = _spawnSystem.spawnInZone(current, zoneId, card.enemyId, card.count);

      // Zombicide rule: each fatty spawn also brings 2 walkers.
      if (card.type == SpawnCardType.fatty) {
        current = _spawnSystem.spawnInZone(current, zoneId, 'drone_walker', 2);
        _log.spawn(zoneId, 'Corrupted Scout Drone', 2);
      }

      spawnSteps.add(SpawnStep(
        zoneId:    zoneId,
        zoneName:  zoneId,
        enemyId:   card.enemyId,
        enemyName: def.name,
        tier:      def.tier,
        count:     card.count,
      ));
    }
    return (state: current, spawnSteps: spawnSteps);
  }

  GameState beginNextRound(GameState state, MissionDefinition mission) {
    if (state.outcome != GameOutcome.none) {
      if (state.outcome == GameOutcome.victory) _log.victory();
      if (state.outcome == GameOutcome.defeat)  _log.defeat();
      return state;
    }

    final alive = state.players.where((p) => !p.isEliminated).toList();
    if (alive.isEmpty) {
      _log.defeat();
      return state.copyWith(outcome: GameOutcome.defeat);
    }

    var next = NoiseSystem.clearNoise(state);

    final resetPlayers = next.players.map((p) => p.copyWith(
      actionsRemaining:        p.isEliminated ? 0 : SkillSystem.actionsPerTurn(p),
      zonesMovedThisTurn:      0,
      dangerLevel:             p.currentDangerLevel,
      resistanceUsedThisTurn: false,
    )).toList();

    final newRound = state.round + 1;
    _log.roundStart(newRound);
    _log.alertChange(state.alertLevel, next.alertLevel);
    for (final e in next.enemies) {
      // ignore: avoid_print
      print('[BP_LOG][R$newRound][ENEMY_ON_BOARD] ${e.definitionId} [${e.instanceId.substring(0, 8)}] at ${e.zoneId} hp:${e.currentHp}');
    }

    return next.copyWith(
      round:          newRound,
      phase:          GamePhase.playerTurn,
      players:        resetPlayers,
      activePlayerId: alive.first.playerId,
      eventLog:       [...next.eventLog, '── Round $newRound ──'].takeLast(20).toList(),
    );
  }

  // ---- Helpers ----

  GameState _checkVictory(GameState state) {
    final allDone = state.objectives.where((o) => o.isPrimary).every((o) => o.isCompleted);
    return allDone ? state.copyWith(outcome: GameOutcome.victory) : state;
  }

  static int _playerIdx(GameState state, String playerId) {
    final idx = state.players.indexWhere((p) => p.playerId == playerId);
    assert(idx != -1);
    return idx;
  }

  static GameState _updatePlayer(GameState state, int idx, PlayerState updated) {
    final players = List<PlayerState>.from(state.players)..[idx] = updated;
    return state.copyWith(players: players);
  }

  static PlayerState _addItemToInventory(PlayerState p, String itemId) {
    if (p.equippedLeft == null)  return p.copyWith(equippedLeft: itemId);
    if (p.equippedRight == null) return p.copyWith(equippedRight: itemId);
    if (p.backpack.length < 3)   return p.copyWith(backpack: [...p.backpack, itemId]);
    return p;
  }
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
