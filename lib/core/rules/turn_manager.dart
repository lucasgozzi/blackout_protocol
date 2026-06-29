import '../models/game_state.dart';
import '../models/mission.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/weapon.dart';
import '../engine/enemy_turn_script.dart';
import '../engine/mission_logger.dart';
import 'alert_system.dart';
import 'combat_rules.dart';
import 'movement_rules.dart';
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
  // Zone graph used by enemy AI — set when session starts.
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
  void setMapData(dynamic mapData) {
    _mapData = mapData;
    if (mapData != null) {
      _combatRules.tilePixelSize = mapData.tilePixelSize as int;
    }
  }

  AlertSystem get alertSystem => _alertSystem;
  CombatRules get combatRules => _combatRules;
  SpawnSystem get spawnSystem => _spawnSystem;

  // ---- OPEN DOOR (1 action, any number of times per turn) ----

  bool canOpenDoor(PlayerState player) => player.actionsRemaining > 0;

  GameState openDoor(GameState state, String playerId, String fromZoneId, String toZoneId) {
    final idx = _playerIdx(state, playerId);
    final player = state.players[idx];
    if (!canOpenDoor(player)) return state;

    final key = '$fromZoneId|$toZoneId';
    final alreadyOpen = state.openDoors.contains(key) ||
        state.openDoors.contains('$toZoneId|$fromZoneId');
    if (alreadyOpen) return state;

    // freeOpenDoor skill: no action cost.
    final free = SkillSystem.freeOpenDoor(player);
    final updatedPlayer = free
        ? player
        : player.copyWith(actionsRemaining: player.actionsRemaining - 1);
    _log.playerOpenDoor(player.definitionId, fromZoneId, toZoneId);
    final log = '${player.definitionId} abriu porta → $toZoneId${free ? " (grátis)" : ""}';

    return state.copyWith(
      players: List<PlayerState>.from(state.players)..[idx] = updatedPlayer,
      openDoors: [...state.openDoors, key],
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  // ---- MOVE (1 action per zone, up to movementRange zones per turn) ----

  bool canMove(PlayerState player) {
    final maxZones = SkillSystem.movementRange(player);
    return player.actionsRemaining > 0 && player.zonesMovedThisTurn < maxZones;
  }

  GameState movePlayer(GameState state, String playerId, int tx, int ty) {
    final idx = _playerIdx(state, playerId);
    final player = state.players[idx];
    assert(canMove(player), 'Player has no movement remaining');

    _log.playerMove(player.definitionId, '(${player.x},${player.y})', '($tx,$ty)');

    final updated = player.copyWith(
      x: tx, y: ty,
      actionsRemaining: player.actionsRemaining - 1,
      zonesMovedThisTurn: player.zonesMovedThisTurn + 1,
    );
    final logMsg = '${player.definitionId} → ($tx,$ty)';
    final newState = _updatePlayer(state, idx, updated);
    return newState.copyWith(
      eventLog: [...newState.eventLog, logMsg].takeLast(20).toList(),
    );
  }

  // ---- ATTACK ZONE (1 action, up to 3x per turn) ----

  ZoneCombatResult attackZone(
    GameState state,
    String playerId,
    WeaponDefinition weapon,
    int targetX,
    int targetY,
  ) {
    var result = _combatRules.attackZone(state, playerId, weapon, targetX, targetY);

    // Add noise if weapon is noisy.
    if (weapon.isNoisy) {
      result = ZoneCombatResult(
        state: NoiseSystem.addNoise(result.state, targetX, targetY, 1),
        log: result.log,
      );
    }

    return result;
  }

  // ---- SEARCH (1 action, up to 3x per turn) ----

  /// Draws loot and deducts the action. For objective tiles the item is placed
  /// automatically (no player choice). For random loot, returns the loot id so
  /// the caller can show a placement UI — the item is NOT added to inventory yet.
  ({GameState state, String? pendingLootId}) search(
    GameState state,
    String playerId,
    String? objectiveId,
  ) {
    final idx = _playerIdx(state, playerId);
    final player = state.players[idx];
    if (player.actionsRemaining <= 0) return (state: state, pendingLootId: null);

    // Objective tile — auto-place and complete objective (no choice needed).
    if (objectiveId != null && objectiveId.isNotEmpty) {
      final objIdx = state.objectives.indexWhere((o) => o.id == objectiveId);
      if (objIdx != -1 && !state.objectives[objIdx].isCompleted) {
        final updatedObj = List.of(state.objectives)
          ..[objIdx] = state.objectives[objIdx].copyWith(isCompleted: true);
        final updatedPlayer = _addItemToInventory(
          player.copyWith(actionsRemaining: player.actionsRemaining - 1),
          objectiveId,
        );
        final log = '${player.definitionId} encontrou: ${state.objectives[objIdx].description}';
        final newState = state.copyWith(
          objectives: updatedObj,
          players: List.of(state.players)..[idx] = updatedPlayer,
          eventLog: [...state.eventLog, log].takeLast(20).toList(),
        );
        return (state: _checkVictory(newState), pendingLootId: null);
      }
    }

    // Random loot draw — deduct action, apply skill, but do NOT place item yet.
    final loot = searchSystem?.draw();
    final isUseful = loot != null && !loot.isNothing;
    var afterAction = player.copyWith(actionsRemaining: player.actionsRemaining - 1);

    // healOnSearch skill: recover one danger level.
    if (SkillSystem.healOnSearch(player) && player.dangerLevel != DangerLevel.blue) {
      afterAction = SkillSystem.applyHeal(afterAction);
    }

    _log.playerSearch(player.definitionId, isUseful ? loot!.id : null);
    final log = isUseful
        ? '${player.definitionId} encontrou: ${loot!.name}'
        : '${player.definitionId} buscou — nada encontrado';

    return (
      state: state.copyWith(
        players: List.of(state.players)..[idx] = afterAction,
        eventLog: [...state.eventLog, log].takeLast(20).toList(),
      ),
      pendingLootId: isUseful ? loot!.id : null,
    );
  }

  /// Places a previously drawn loot item into the chosen slot.
  /// [slot]: 'left' | 'right' | 'backpack'
  GameState placeLoot(GameState state, String playerId, String itemId, String slot) {
    final idx = _playerIdx(state, playerId);
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
        if (player.backpack.length >= 3) return state; // full
        updated = player.copyWith(backpack: [...player.backpack, itemId]);
      default:
        return state;
    }

    return state.copyWith(
      players: List.of(state.players)..[idx] = updated,
    );
  }

  // ---- TRADE ITEM (1 action, survivors must be in same zone) ----

  bool canTrade(PlayerState from, PlayerState to) =>
      from.actionsRemaining > 0 &&
      !from.isEliminated &&
      !to.isEliminated &&
      from.x == to.x &&
      from.y == to.y;

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
    if (to.inventoryFull)    return state;

    // Remove item from sender.
    PlayerState updatedFrom;
    if (from.equippedLeft == itemId) {
      updatedFrom = from.copyWith(equippedLeft: null, actionsRemaining: from.actionsRemaining - 1);
    } else if (from.equippedRight == itemId) {
      updatedFrom = from.copyWith(equippedRight: null, actionsRemaining: from.actionsRemaining - 1);
    } else if (from.backpack.contains(itemId)) {
      final bp = List<String>.from(from.backpack)..remove(itemId);
      updatedFrom = from.copyWith(backpack: bp, actionsRemaining: from.actionsRemaining - 1);
    } else {
      return state; // item not found
    }

    // Give item to receiver (prefers hand slots).
    PlayerState updatedTo;
    if (to.equippedLeft == null) {
      updatedTo = to.copyWith(equippedLeft: itemId);
    } else if (to.equippedRight == null) {
      updatedTo = to.copyWith(equippedRight: itemId);
    } else {
      updatedTo = to.copyWith(backpack: [...to.backpack, itemId]);
    }

    final log = '${from.definitionId} deu $itemId para ${to.definitionId}';
    final players = List<PlayerState>.from(state.players)
      ..[fromIdx] = updatedFrom
      ..[toIdx]   = updatedTo;

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

  /// Returns the new game state, a cinematic script, and whether the enemy
  /// phase actually ran (so the caller knows to call beginNextRound).
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
      // Log state of all players before enemy phase
      for (final p in alive) {
        _log.playerState(p.definitionId, p.dangerLevel.name, p.xp,
            p.actionsRemaining, p.zonesMovedThisTurn, SkillSystem.movementRange(p));
      }
      _log.enemyPhaseStart();
      final r = _beginEnemyPhase(state);
      return (state: r.state, script: r.script, enemyPhaseRan: true);
    }
    _log.endPlayerTurn(state.players.firstWhere((p) => p.playerId == state.activePlayerId).definitionId,
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

    // Collapse individual EnemyMoveSteps into EnemyGroupMoveSteps per definitionId,
    // preserving relative order among non-move steps (attacks, spawns).
    final steps = _groupMoveSteps(rawSteps);
    steps.addAll(alertResult.spawnSteps);

    return (state: alertResult.state, script: EnemyTurnScript(steps));
  }

  /// Replaces consecutive (or scattered) EnemyMoveSteps of the same definitionId
  /// with a single EnemyGroupMoveStep. Non-move steps keep their position.
  List<EnemyTurnStep> _groupMoveSteps(List<EnemyTurnStep> raw) {
    // Collect all move steps grouped by definitionId in encounter order.
    final movesByDef = <String, List<EnemyMoveStep>>{};
    final defOrder   = <String>[];
    for (final s in raw) {
      if (s is EnemyMoveStep) {
        if (!movesByDef.containsKey(s.definitionId)) {
          movesByDef[s.definitionId] = [];
          defOrder.add(s.definitionId);
        }
        movesByDef[s.definitionId]!.add(s);
      }
    }

    // Build result: replace first occurrence of each defId's moves with the group,
    // drop subsequent individual moves for that defId.
    final emitted = <String>{};
    final result  = <EnemyTurnStep>[];
    for (final s in raw) {
      if (s is EnemyMoveStep) {
        if (emitted.contains(s.definitionId)) continue;
        emitted.add(s.definitionId);
        final group = movesByDef[s.definitionId]!;
        final def = _catalog.getById(s.definitionId);
        result.add(EnemyGroupMoveStep(
          definitionId: s.definitionId,
          enemyName:    s.enemyName,
          tier:         s.tier,
          moves:        group,
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
    final actions = def.actions; // read from enemy JSON, not hardcoded by tier

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
          enemy: def.name, instanceId: currentEnemy.instanceId,
          target: survivor.definitionId,
          dangerBefore: dangerBefore.name, dangerAfter: afterState.dangerLevel.name,
          eliminated: afterState.isEliminated,
        );
        steps.add(EnemyAttackStep(
          instanceId:       currentEnemy.instanceId,
          definitionId:     def.id,
          enemyName:        def.name,
          tier:             def.tier,
          worldX:           currentEnemy.x,
          worldY:           currentEnemy.y,
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
      final newPos = _zoneCenterFor(nextZoneId);
      if (newPos == null) continue;

      _log.enemyMove(def.name, currentEnemy.instanceId,
          '(${currentEnemy.x},${currentEnemy.y})', '(${newPos.$1},${newPos.$2})');
      steps.add(EnemyMoveStep(
        instanceId:   currentEnemy.instanceId,
        definitionId: def.id,
        enemyName:    def.name,
        tier:         def.tier,
        fromX: currentEnemy.x, fromY: currentEnemy.y,
        toX: newPos.$1,        toY: newPos.$2,
      ));

      final moved   = currentEnemy.copyWith(x: newPos.$1, y: newPos.$2, activated: true);
      final enemies = List<EnemyInstance>.from(current.enemies);
      final idx     = enemies.indexWhere((e) => e.instanceId == currentEnemy.instanceId);
      if (idx != -1) enemies[idx] = moved;
      final log = '${def.name} move → $nextZoneId';
      current = current.copyWith(
        enemies:  enemies,
        eventLog: [...current.eventLog, log].takeLast(20).toList(),
      );
    }
    return (state: current, steps: steps);
  }

  // Survivor in same zone as enemy — uses actual zone IDs when map is loaded,
  // falls back to a tight radius (half tile) otherwise.
  PlayerState? _survivorInSameZone(EnemyInstance enemy, GameState state) {
    final mapData = _mapData;
    if (mapData != null) {
      final enemyZone = _zoneIdForPos(enemy.x, enemy.y);
      if (enemyZone != null) {
        try {
          return state.players.firstWhere((p) =>
              !p.isEliminated &&
              _zoneIdForPos(p.x, p.y) == enemyZone);
        } catch (_) { return null; }
      }
    }
    // Fallback: half-tile radius so adjacent zones don't bleed.
    final r = (_mapData?.tilePixelSize ?? 200) * 0.5;
    try {
      return state.players.firstWhere((p) =>
          !p.isEliminated &&
          (p.x - enemy.x).abs() <= r &&
          (p.y - enemy.y).abs() <= r);
    } catch (_) { return null; }
  }

  // Zombicide AI:
  // 1. Zone with a visible survivor (most survivors wins)
  // 2. Zone with most noise tokens that enemy can see
  // 3. Noisiest zone on map
  // 4. Nearest survivor
  String? _chooseTargetZoneId(GameState state, EnemyInstance enemy) {
    final alive = state.players.where((p) => !p.isEliminated).toList();
    if (alive.isEmpty) return null;

    final enemyZoneId = _zoneIdForPos(enemy.x, enemy.y);
    if (enemyZoneId == null) {
      // Fallback: go to nearest alive player's zone.
      final nearest = _nearestAlivePlayer(enemy.x, enemy.y, alive);
      return nearest != null ? _zoneIdForPos(nearest.x, nearest.y) : null;
    }

    // 1. Survivors in visible adjacent zones (including current zone).
    final visibleZones = _visibleZones(enemyZoneId);
    final survivorZoneCounts = <String, int>{};
    for (final p in alive) {
      final pZone = _zoneIdForPos(p.x, p.y);
      if (pZone != null && visibleZones.contains(pZone)) {
        survivorZoneCounts[pZone] = (survivorZoneCounts[pZone] ?? 0) + 1;
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
      if (noise > maxNoise) { maxNoise = noise; noisiest = zoneId; }
    }
    if (noisiest != null) return noisiest;

    // 3. Noisiest zone on whole map.
    if (state.noiseTokens.isNotEmpty) {
      return state.noiseTokens.entries
          .reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    // 4. Nearest alive player's zone.
    final nearest = _nearestAlivePlayer(enemy.x, enemy.y, alive);
    return nearest != null ? _zoneIdForPos(nearest.x, nearest.y) : null;
  }

  // BFS on zone graph to find next zone to move toward targetZoneId.
  String? _nextZoneToward(EnemyInstance enemy, String targetZoneId, GameState state) {
    final fromZoneId = _zoneIdForPos(enemy.x, enemy.y);
    if (fromZoneId == null || fromZoneId == targetZoneId) return null;

    final mapData = _mapData;
    if (mapData == null) return null;

    // BFS to find shortest path.
    final prev = <String, String?>{fromZoneId: null};
    final queue = [fromZoneId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == targetZoneId) break;
      final adjs = _adjacentZoneIds(current);
      for (final adj in adjs) {
        if (!prev.containsKey(adj)) {
          prev[adj] = current;
          queue.add(adj);
        }
      }
    }

    if (!prev.containsKey(targetZoneId)) return null;

    // Trace back to find first step from fromZoneId.
    String? step = targetZoneId;
    while (prev[step] != fromZoneId && prev[step] != null) {
      step = prev[step];
    }
    return step;
  }

  // Get zone center world coords from spawnZoneCoords or MapData.
  (int, int)? _zoneCenterFor(String zoneId) {
    final mapData = _mapData;
    if (mapData == null) return null;
    try {
      final found = mapData.findZone(zoneId);
      if (found == null) return null;
      final c = mapData.zoneCenter(found.tile, found.zone);
      return (c.x.toInt(), c.y.toInt());
    } catch (_) { return null; }
  }

  // Find zone id for a world position — radius scales with tilePixelSize.
  String? _zoneIdForPos(int worldX, int worldY) {
    final mapData = _mapData;
    if (mapData == null) return null;
    try {
      final r = mapData.tilePixelSize * 1.25;
      for (final tile in mapData.tiles) {
        final tr = mapData.tileWorldRect(tile);
        if (worldX >= tr.x - r && worldX <= tr.x + tr.w + r &&
            worldY >= tr.y - r && worldY <= tr.y + tr.h + r) {
          for (final zone in tile.zones) {
            final zx = tr.x + zone.rect.x * tr.w;
            final zy = tr.y + zone.rect.y * tr.h;
            final zw = zone.rect.w * tr.w;
            final zh = zone.rect.h * tr.h;
            if (worldX >= zx - r && worldX <= zx + zw + r &&
                worldY >= zy - r && worldY <= zy + zh + r) {
              return zone.id;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // Zones visible from a given zone (current + adjacent open/door-open).
  Set<String> _visibleZones(String fromZoneId) {
    final result = <String>{fromZoneId};
    result.addAll(_adjacentZoneIds(fromZoneId));
    return result;
  }

  // Adjacent zone ids using MapData zone graph.
  List<String> _adjacentZoneIds(String zoneId) {
    final mapData = _mapData;
    if (mapData == null) return [];
    try {
      return mapData.adjacentZones(zoneId).map<String>((e) => e.zone.id as String).toList();
    } catch (_) { return []; }
  }

  // ---- ALERT PHASE ----

  ({GameState state, List<SpawnStep> spawnSteps}) _beginAlertPhase(GameState state) {
    final phaseState = state.copyWith(phase: GamePhase.alertPhase);
    final mission = _mission;
    if (mission == null) return (state: phaseState, spawnSteps: []);

    final alertResult = _alertSystem.increment(phaseState, mission);
    var current = alertResult.state;
    for (final event in alertResult.triggered) {
      current = _spawnSystem.spawnFromEvent(current, mission, event);
    }

    final deck = spawnDeck;
    final List<SpawnStep> spawnSteps;
    if (deck != null && (mission.spawnPoints.isNotEmpty || current.spawnZoneCoords.isNotEmpty)) {
      final result = _spawnFromDeck(current, mission, deck);
      current    = result.state;
      spawnSteps = result.spawnSteps;
    } else {
      current    = _spawnSystem.spawnForAlertLevel(current, mission);
      spawnSteps = [];
    }

    return (state: current, spawnSteps: spawnSteps);
  }

  /// Zombicide spawn: each spawn zone draws one card, places enemies, and
  /// records a SpawnStep for the cinematic overlay.
  ({GameState state, List<SpawnStep> spawnSteps}) _spawnFromDeck(
    GameState state,
    MissionDefinition mission,
    SpawnDeck deck,
  ) {
    final spawnZones = state.spawnZoneCoords.keys.toList();
    final spawnIds   = spawnZones.isNotEmpty
        ? spawnZones
        : mission.spawnPoints.map((s) => s.id).toList();

    var current              = state;
    final spawnSteps         = <SpawnStep>[];

    for (final zoneId in spawnIds) {
      if (current.outcome != GameOutcome.none) break;

      final card = deck.draw();
      if (card.type == SpawnCardType.abomination && state.alertLevel < 7) continue;

      final def = _catalog.getById(card.enemyId);

      if (spawnZones.isNotEmpty) {
        // Resolve world coords for this zone.
        final coordStr = current.spawnZoneCoords[zoneId];
        int wx = 0, wy = 0;
        if (coordStr != null) {
          final p = coordStr.split(',');
          wx = int.tryParse(p[0]) ?? 0;
          wy = int.tryParse(p[1]) ?? 0;
        }
        // ignore: avoid_print
        print('[BP_LOG][SPAWN_DEBUG] zoneId=$zoneId coordStr=$coordStr wx=$wx wy=$wy knownZones=${current.spawnZoneCoords.keys.toList()}');
        _log.spawn(zoneId, def.name, card.count);
        current = _spawnSystem.spawnInZone(current, zoneId, card.enemyId, card.count);
        spawnSteps.add(SpawnStep(
          zoneId:    zoneId,
          zoneName:  zoneId,
          enemyId:   card.enemyId,
          enemyName: def.name,
          tier:      def.tier,
          count:     card.count,
          worldX:    wx,
          worldY:    wy,
        ));
      } else {
        final sp = mission.spawnPoints.firstWhere(
          (s) => s.id == zoneId, orElse: () => mission.spawnPoints.first);
        final fakeRule = SpawnRule(
          alertLevel:  state.alertLevel,
          enemyId:     card.enemyId,
          count:       card.count,
          spawnPointId: zoneId,
        );
        current = _spawnSystem.spawnForAlertLevel(
            current, mission.copyWith(spawnRules: [fakeRule]));
        spawnSteps.add(SpawnStep(
          zoneId:    zoneId,
          zoneName:  zoneId,
          enemyId:   card.enemyId,
          enemyName: def.name,
          tier:      def.tier,
          count:     card.count,
          worldX:    sp.x,
          worldY:    sp.y,
        ));
      }
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

    // Clear noise tokens at end of zombie phase.
    var next = NoiseSystem.clearNoise(state);

    final resetPlayers = next.players.map((p) => p.copyWith(
      actionsRemaining: p.isEliminated ? 0 : SkillSystem.actionsPerTurn(p),
      zonesMovedThisTurn: 0,
      dangerLevel: p.currentDangerLevel,
    )).toList();

    final newRound = state.round + 1;
    _log.roundStart(newRound);
    _log.alertChange(state.alertLevel, next.alertLevel);
    // Log enemies on the board at start of round
    for (final e in next.enemies) {
      // ignore: avoid_print
      print('[BP_LOG][R$newRound][ENEMY_ON_BOARD] ${e.definitionId} [${e.instanceId.substring(0,8)}] at (${e.x},${e.y}) hp:${e.currentHp}');
    }

    return next.copyWith(
      round: newRound,
      phase: GamePhase.playerTurn,
      players: resetPlayers,
      activePlayerId: alive.first.playerId,
      eventLog: [...next.eventLog, '── Round $newRound ──'].takeLast(20).toList(),
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

  static PlayerState? _nearestAlivePlayer(int x, int y, List<PlayerState> players) {
    if (players.isEmpty) return null;
    final sorted = List<PlayerState>.from(players)
      ..sort((a, b) =>
          ((a.x - x).abs() + (a.y - y).abs()).compareTo((b.x - x).abs() + (b.y - y).abs()));
    return sorted.first;
  }

  static PlayerState? _adjacentAlivePlayer(int x, int y, List<PlayerState> players) {
    try {
      return players.firstWhere(
        (p) => !p.isEliminated && (p.x - x).abs() + (p.y - y).abs() <= 1,
      );
    } catch (_) {
      return null;
    }
  }

  static PlayerState _addItemToInventory(PlayerState p, String itemId) {
    if (p.equippedLeft == null)  return p.copyWith(equippedLeft: itemId);
    if (p.equippedRight == null) return p.copyWith(equippedRight: itemId);
    if (p.backpack.length < 3)   return p.copyWith(backpack: [...p.backpack, itemId]);
    return p; // inventory full
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
