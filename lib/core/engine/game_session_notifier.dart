import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/game_state.dart';
import '../models/mission.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/enemy.dart' show EnemyTier;
import '../models/spawn_event.dart';
import '../models/weapon.dart';
import '../rules/combat_rules.dart';
import '../rules/alert_system.dart';
import '../rules/search_system.dart';
import '../rules/spawn_deck.dart';
import '../rules/spawn_system.dart';
import '../rules/turn_manager.dart';
import '../engine/enemy_turn_script.dart';
import '../engine/mission_logger.dart';
import '../../data/enemy_catalog.dart';
import '../../data/map_loader.dart';
import '../../data/weapon_catalog.dart';
import '../../data/asset_loader.dart';
import 'game_context.dart';

const _uuid = Uuid();

class SessionState {
  final GameState game;
  final MissionDefinition mission;
  final bool isLoaded;
  // Non-null while player must choose where to place a searched item.
  final String? pendingLootId;
  final String? pendingLootPlayerId;
  // Non-null while the enemy-phase cinematic is playing.
  final EnemyTurnScript? cinematicScript;

  const SessionState({
    required this.game,
    required this.mission,
    required this.isLoaded,
    this.pendingLootId,
    this.pendingLootPlayerId,
    this.cinematicScript,
  });

  SessionState copyWith({
    GameState? game,
    MissionDefinition? mission,
    bool? isLoaded,
    String? pendingLootId,
    String? pendingLootPlayerId,
    bool clearPendingLoot = false,
    EnemyTurnScript? cinematicScript,
    bool clearCinematic = false,
  }) => SessionState(
    game: game ?? this.game,
    mission: mission ?? this.mission,
    isLoaded: isLoaded ?? this.isLoaded,
    pendingLootId: clearPendingLoot ? null : (pendingLootId ?? this.pendingLootId),
    pendingLootPlayerId: clearPendingLoot ? null : (pendingLootPlayerId ?? this.pendingLootPlayerId),
    cinematicScript: clearCinematic ? null : (cinematicScript ?? this.cinematicScript),
  );
}

class GameSessionNotifier extends Notifier<SessionState?> {
  EnemyCatalog?  _enemyCatalog;
  WeaponCatalog? _weaponCatalog;
  TurnManager?   _turnManager;

  @override
  SessionState? build() => null;

  void init(EnemyCatalog enemyCatalog) {
    if (_enemyCatalog != null) return;
    _enemyCatalog = enemyCatalog;
    final adapter = _CatalogAdapter(enemyCatalog);
    _turnManager = TurnManager(
      alertSystem: AlertSystem(),
      combatRules: CombatRules(),
      spawnSystem: SpawnSystem(catalog: adapter),
      catalog: adapter,
    );
    _loadAssets();
  }

  void _loadMapForAI(MissionDefinition mission) {
    final mapId = mission.mapAsset
        .split('/').last.replaceAll('.tmj', '').replaceAll('.json', '');
    MapLoader(FlutterAssetLoader()).load(mapId).then((mapData) {
      _turnManager?.setMapData(mapData);
    }).catchError((_) {});
  }

  Future<void> _loadAssets() async {
    final loader = FlutterAssetLoader();
    try {
      final lootJson = await loader.loadJson('assets/data/loot/loot_table.json');
      _turnManager?.searchSystem = SearchSystem.fromJson(lootJson);
    } catch (_) {}
    try {
      final weaponJson = await loader.loadJson('assets/data/weapons/weapons.json');
      _weaponCatalog = WeaponCatalog.fromMap(
        {for (final w in (weaponJson['weapons'] as List)
            .map((e) => WeaponDefinition.fromJson(e as Map<String, dynamic>)))
          w.id: w},
      );
    } catch (_) {}
  }

  // ---- Session lifecycle ----

  void startMission(
    MissionDefinition mission,
    List<PlayerDefinition> selectedPlayers, {
    List<({int x, int y})> startPositions = const [],
    Map<String, String> spawnZoneCoords = const {},
  }) {
    MissionLogger.instance.reset();
    MissionLogger.instance.roundStart(1);
    final players = selectedPlayers.mapIndexed((i, def) {
      final pos = i < startPositions.length ? startPositions[i] : (x: 1 + i, y: 1);
      return PlayerState(
        playerId: _uuid.v4(),
        definitionId: def.id,
        x: pos.x, y: pos.y,
        actionsRemaining: 3,
        xp: 0,
        dangerLevel: DangerLevel.blue,
        movementRange: def.movementRange,
        equippedLeft: def.startingWeapon.isNotEmpty ? def.startingWeapon : null,
      );
    }).toList();

    final gameState = GameState(
      sessionId: _uuid.v4(),
      missionId: mission.id,
      round: 1,
      phase: GamePhase.playerTurn,
      alertLevel: 0,
      players: players,
      enemies: [],
      objectives: mission.objectives,
      activePlayerId: players.first.playerId,
      outcome: GameOutcome.none,
      eventLog: ['── Round 1 ──'],
      spawnZoneCoords: spawnZoneCoords,
    );
    _turnManager?.setMission(mission);
    _turnManager?.spawnDeck = mission.spawnDeck.isNotEmpty
        ? SpawnDeck.fromJson({'cards': mission.spawnDeck})
        : SpawnDeck.campaign01();
    _loadMapForAI(mission);
    state = SessionState(game: gameState, mission: mission, isLoaded: true);
  }

  void loadContext(GameContext ctx, MissionDefinition mission) {
    _turnManager?.setMission(mission);
    _turnManager?.spawnDeck = mission.spawnDeck.isNotEmpty
        ? SpawnDeck.fromJson({'cards': mission.spawnDeck})
        : SpawnDeck.campaign01();
    _loadMapForAI(mission);
    state = SessionState(game: ctx.toGameState(), mission: mission, isLoaded: true);
  }

  void endSession() => state = null;

  // ---- Player actions ----

  void movePlayer(String playerId, int tx, int ty) {
    final s = _requireSession();
    final player = s.game.players.firstWhere((p) => p.playerId == playerId);
    if (!_turnManager!.canMove(player)) return;
    final newGame = _turnManager!.movePlayer(s.game, playerId, tx, ty);
    state = s.copyWith(game: newGame);
  }

  /// Zombicide zone attack — targets all actors in the zone by priority.
  void attackZone(String playerId, String weaponId, int targetX, int targetY) {
    final s = _requireSession();
    final weapon = _weaponCatalog?.getById(weaponId) ?? WeaponDefinition.fists;
    final result = _turnManager!.attackZone(s.game, playerId, weapon, targetX, targetY);
    state = s.copyWith(game: result.state);
  }

  /// Attack by zone ID — finds enemies whose position matches the zone coords.
  void attackZoneById(String playerId, String weaponId, String zoneId) {
    final s = _requireSession();
    final weapon = _weaponCatalog?.getById(weaponId) ?? WeaponDefinition.fists;

    // Find enemies that "belong" to this zone using spawnZoneCoords as reference,
    // or just attack all enemies if zone coords aren't available.
    // We match enemies by finding the closest group to the zone center.
    final coordStr = s.game.spawnZoneCoords[zoneId];
    int cx = 0, cy = 0;
    if (coordStr != null) {
      final p = coordStr.split(',');
      cx = int.tryParse(p[0]) ?? 0;
      cy = int.tryParse(p[1]) ?? 0;
    }

    // If we have zone coords, find enemies near that point (within 300px).
    // Otherwise fall back to any enemy position.
    final enemies = s.game.enemies;
    if (enemies.isEmpty) return;

    int tx, ty;
    if (coordStr != null) {
      // Use zone center — CombatRules will find enemies within radius.
      tx = cx; ty = cy;
    } else {
      // Use first enemy's position.
      tx = enemies.first.x; ty = enemies.first.y;
    }

    final result = _turnManager!.attackZone(s.game, playerId, weapon, tx, ty);
    state = s.copyWith(game: result.state);
  }

  /// Legacy single-enemy attack — wraps zone attack on enemy's tile.
  void attackEnemy(String playerId, String enemyInstanceId) {
    final s = _requireSession();
    final enemy = s.game.enemies.firstWhere((e) => e.instanceId == enemyInstanceId);
    final player = s.game.players.firstWhere((p) => p.playerId == playerId);
    final weaponId = player.equippedLeft ?? player.equippedRight ?? 'fists';
    attackZone(playerId, weaponId, enemy.x, enemy.y);
  }

  void openDoor(String playerId, String fromZoneId, String toZoneId) {
    final s = _requireSession();
    final newGame = _turnManager!.openDoor(s.game, playerId, fromZoneId, toZoneId);
    state = s.copyWith(game: newGame);
  }

  void search(String playerId, String? objectiveId) {
    final s = _requireSession();
    final result = _turnManager!.search(s.game, playerId, objectiveId);
    if (result.pendingLootId != null) {
      state = s.copyWith(
        game: result.state,
        pendingLootId: result.pendingLootId,
        pendingLootPlayerId: playerId,
      );
    } else {
      state = s.copyWith(game: result.state);
    }
  }

  /// Place the pending loot item into the chosen slot and clear the pending state.
  /// [slot]: 'left' | 'right' | 'backpack'
  void placeLoot(String slot) {
    final s = _requireSession();
    final lootId   = s.pendingLootId;
    final playerId = s.pendingLootPlayerId;
    if (lootId == null || playerId == null) return;
    final newGame = _turnManager!.placeLoot(s.game, playerId, lootId, slot);
    state = s.copyWith(game: newGame, clearPendingLoot: true);
  }

  /// Discard the pending loot without placing it anywhere.
  void discardLoot() {
    final s = _requireSession();
    if (s.pendingLootId == null) return;
    state = s.copyWith(clearPendingLoot: true);
  }

  void interact(String playerId, String objectiveId) => search(playerId, objectiveId);

  void clearCombatLog() {
    final s = _requireSession();
    state = s.copyWith(game: s.game.copyWith(lastCombatLog: null));
  }

  void clearSpawnEvents() {
    final s = _requireSession();
    state = s.copyWith(game: s.game.copyWith(pendingSpawnMaps: []));
  }

  void tradeItem(String fromPlayerId, String toPlayerId, String itemId) {
    final s = _requireSession();
    final newGame = _turnManager!.tradeItem(s.game, fromPlayerId, toPlayerId, itemId);
    state = s.copyWith(game: newGame);
  }

  /// Equip item from backpack to hand slot. Costs 1 action.
  void equipItem(String playerId, String itemId, {bool toLeft = true}) {
    final s   = _requireSession();
    final idx = s.game.players.indexWhere((p) => p.playerId == playerId);
    if (idx == -1) return;
    final p = s.game.players[idx];
    if (p.actionsRemaining <= 0) return;

    // Move item: remove from backpack (if it's there), put in hand.
    // If already in a hand slot, just swap.
    final bp = List<String>.from(p.backpack)..remove(itemId);

    // What was in the target hand goes to backpack.
    final displaced = toLeft ? p.equippedLeft : p.equippedRight;
    if (displaced != null && displaced != itemId) bp.add(displaced);

    final updated = toLeft
        ? p.copyWith(equippedLeft: itemId, backpack: bp, actionsRemaining: p.actionsRemaining - 1)
        : p.copyWith(equippedRight: itemId, backpack: bp, actionsRemaining: p.actionsRemaining - 1);

    final players = List<PlayerState>.from(s.game.players)..[idx] = updated;
    final log = '${p.definitionId} equipou: $itemId';
    state = s.copyWith(game: s.game.copyWith(
      players: players,
      eventLog: [...s.game.eventLog, log].takeLast(20).toList(),
    ));
  }

  void endPlayerTurn() {
    final s = _requireSession();
    final result = _turnManager!.endPlayerTurn(s.game);
    var newGame  = result.state;
    final script = result.script;

    // beginNextRound only when the enemy/alert phase actually ran.
    // For mid-rotation turns (enemyPhaseRan=false), activePlayerId was already
    // advanced inside endPlayerTurn and must not be reset.
    if (result.enemyPhaseRan && newGame.outcome == GameOutcome.none) {
      newGame = _turnManager!.beginNextRound(newGame, s.mission);
    }

    state = s.copyWith(
      game: newGame,
      cinematicScript: script.isEmpty ? null : script,
    );
  }

  void clearCinematic() {
    final s = _requireSession();
    state = s.copyWith(clearCinematic: true);
  }

  void clearWounded() {
    final s = _requireSession();
    state = s.copyWith(game: s.game.copyWith(lastWoundedPlayerId: null));
  }

  SessionState _requireSession() {
    assert(state != null, 'No active game session');
    return state!;
  }

  WeaponDefinition? weaponById(String id) => _weaponCatalog?.getById(id);
  WeaponCatalog? get weaponCatalog => _weaponCatalog;
}

// ---- Providers ----

final gameSessionProvider = NotifierProvider<GameSessionNotifier, SessionState?>(
  GameSessionNotifier.new,
);

final activePlayerProvider = Provider<PlayerState?>((ref) {
  final s = ref.watch(gameSessionProvider);
  if (s == null) return null;
  try {
    return s.game.players.firstWhere((p) => p.playerId == s.game.activePlayerId);
  } catch (_) {
    return s.game.players.isNotEmpty ? s.game.players.first : null;
  }
});

final lastWoundedPlayerProvider = Provider<String?>(
  (ref) => ref.watch(gameSessionProvider)?.game.lastWoundedPlayerId,
);

final enemyCinematicProvider = Provider<EnemyTurnScript?>(
  (ref) => ref.watch(gameSessionProvider)?.cinematicScript,
);

final pendingLootProvider  = Provider<({String lootId, String playerId})?>(
  (ref) {
    final s = ref.watch(gameSessionProvider);
    if (s?.pendingLootId == null || s?.pendingLootPlayerId == null) return null;
    return (lootId: s!.pendingLootId!, playerId: s.pendingLootPlayerId!);
  },
);

final alertLevelProvider  = Provider<int>((ref) => ref.watch(gameSessionProvider)?.game.alertLevel ?? 0);
final gamePhaseProvider   = Provider<GamePhase>((ref) => ref.watch(gameSessionProvider)?.game.phase ?? GamePhase.playerTurn);
final gameOutcomeProvider = Provider<GameOutcome>((ref) => ref.watch(gameSessionProvider)?.game.outcome ?? GameOutcome.none);
final eventLogProvider    = Provider<List<String>>((ref) => ref.watch(gameSessionProvider)?.game.eventLog ?? []);
final lastCombatLogProvider = Provider<ZoneCombatLog?>((ref) =>
    ref.watch(gameSessionProvider)?.game.lastCombatLog);

final pendingSpawnProvider = Provider<List<SpawnEvent>>((ref) {
  final maps = ref.watch(gameSessionProvider)?.game.pendingSpawnMaps ?? [];
  return maps.map((m) => SpawnEvent(
    zoneId:    m['zoneId'] as String,
    zoneName:  m['zoneName'] as String,
    enemyId:   m['enemyId'] as String,
    enemyName: m['enemyName'] as String,
    count:     m['count'] as int,
    tier:      EnemyTier.values.firstWhere(
        (t) => t.name == m['tier'], orElse: () => EnemyTier.walker),
  )).toList();
});

// ---- Internal ----

class _CatalogAdapter implements EnemyCatalogLookup {
  final EnemyCatalog _catalog;
  const _CatalogAdapter(this._catalog);
  @override
  EnemyDefinition getById(String id) => _catalog.getById(id);
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}

extension _IndexedMap<T> on List<T> {
  List<R> mapIndexed<R>(R Function(int i, T item) f) {
    final r = <R>[];
    for (var i = 0; i < length; i++) r.add(f(i, this[i]));
    return r;
  }
}
