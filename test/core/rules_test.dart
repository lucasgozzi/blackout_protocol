import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_protocol/core/models/game_state.dart';
import 'package:blackout_protocol/core/models/player.dart';
import 'package:blackout_protocol/core/models/enemy.dart';
import 'package:blackout_protocol/core/models/mission.dart';
import 'package:blackout_protocol/core/models/tile.dart';
import 'package:blackout_protocol/core/rules/movement_rules.dart';
import 'package:blackout_protocol/core/rules/combat_rules.dart';
import 'package:blackout_protocol/core/rules/alert_system.dart';
import 'package:blackout_protocol/core/rules/spawn_system.dart';

// ---- Test fixtures ----

PlayerState _player({
  String id = 'p1',
  String defId = 'scout_aria',
  int x = 5,
  int y = 5,
  int actions = 3,
  int xp = 0,
  DangerLevel danger = DangerLevel.blue,
  bool eliminated = false,
}) =>
    PlayerState(
      playerId: id,
      definitionId: defId,
      x: x, y: y,
      actionsRemaining: actions,
      xp: xp,
      dangerLevel: danger,
      isEliminated: eliminated,
    );

EnemyInstance _enemyInst({
  String instanceId = 'e1',
  String defId = 'drone_walker',
  int x = 3,
  int y = 3,
  int hp = 1,
}) =>
    EnemyInstance(instanceId: instanceId, definitionId: defId, currentHp: hp, x: x, y: y);

EnemyDefinition _enemyDef({
  String id = 'drone_walker',
  int hp = 1,
  int damage = 1,
  EnemyTier tier = EnemyTier.walker,
  List<String> abilities = const [],
}) =>
    EnemyDefinition(
      id: id, name: id, type: EnemyType.corruptedDrone,
      tier: tier, hp: hp, damage: damage, actions: 1,
      activationPriority: 1, spriteId: '',
      specialAbilities: abilities,
    );

GameState _state({
  List<PlayerState>? players,
  List<EnemyInstance>? enemies,
  int alertLevel = 0,
  GamePhase phase = GamePhase.playerTurn,
}) =>
    GameState(
      sessionId: 'test',
      missionId: 'c01_m01_fuel_depot',
      round: 1,
      phase: phase,
      alertLevel: alertLevel,
      players: players ?? [_player()],
      enemies: enemies ?? [],
      objectives: [],
      activePlayerId: 'p1',
      outcome: GameOutcome.none,
    );

MissionDefinition _mission({
  int maxAlertLevel = 10,
  int maxRounds = 0,
  List<SpawnRule> spawnRules = const [],
  List<AlertEvent> alertEvents = const [],
}) =>
    MissionDefinition(
      id: 'm1',
      campaignId: 'c1',
      missionNumber: 1,
      title: 'Test Mission',
      description: '',
      mapAsset: '',
      maxAlertLevel: maxAlertLevel,
      maxRounds: maxRounds,
      objectives: [],
      spawnPoints: [SpawnPoint(id: 'sp1', x: 0, y: 0, direction: 'S')],
      spawnRules: spawnRules,
      alertEvents: alertEvents,
      availablePlayers: [],
      startingItems: {},
    );

// ---- MovementRules ----

void main() {
  group('MovementRules', () {
    final map = GameMap.flat(10, 10);

    test('returns empty when player has no actions', () {
      final p = _player(actions: 0);
      final result = MovementRules.reachableTiles(p, map, _state(players: [p]));
      expect(result, isEmpty);
    });

    test('player with 1 action reaches exactly 4 adjacent tiles', () {
      final p = _player(x: 5, y: 5, actions: 1);
      final result = MovementRules.reachableTiles(p, map, _state(players: [p]));
      expect(result.keys, containsAll([(5, 4), (5, 6), (4, 5), (6, 5)]));
      expect(result.length, 4);
    });

    test('player with 3 actions reaches BFS diamond of radius 3', () {
      final p = _player(x: 5, y: 5, actions: 3);
      final result = MovementRules.reachableTiles(p, map, _state(players: [p]));
      expect(result.containsKey((5, 2)), isTrue);
      expect(result.containsKey((2, 5)), isTrue);
      expect(result.containsKey((5, 8)), isTrue);
    });

    test('enemy-occupied tile is not reachable', () {
      final p = _player(x: 5, y: 5, actions: 2);
      final enemy = _enemyInst(x: 5, y: 4);
      final state = _state(players: [p], enemies: [enemy]);
      final result = MovementRules.reachableTiles(p, map, state);
      expect(result.containsKey((5, 4)), isFalse);
    });

    test('canAttack returns false when out of range', () {
      final p = _player(x: 0, y: 0, actions: 1);
      expect(MovementRules.canAttack(p, 5, 5, map, range: 1), isFalse);
    });

    test('canAttack returns true for adjacent target', () {
      final p = _player(x: 5, y: 5, actions: 1);
      expect(MovementRules.canAttack(p, 5, 6, map, range: 1), isTrue);
    });

    test('canAttack returns false with no actions remaining', () {
      final p = _player(x: 5, y: 5, actions: 0);
      expect(MovementRules.canAttack(p, 5, 6, map, range: 1), isFalse);
    });

    test('attackableTiles returns 4 tiles for melee range', () {
      final p = _player(x: 5, y: 5, actions: 1);
      final tiles = MovementRules.attackableTiles(p, map, range: 1);
      expect(tiles, containsAll([(5, 4), (5, 6), (4, 5), (6, 5)]));
    });
  });

  // ---- CombatRules ----

  group('CombatRules', () {
    test('guaranteed hit kills walker (hp=1)', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final initialState = _state(
        players: [_player()],
        enemies: [_enemyInst(instanceId: 'e1', hp: 1)],
      );
      final def = _enemyDef(hp: 1);
      final attack = rules.playerAttack(initialState, 'p1', 'e1', def, diceCount: 1);

      expect(attack.result.hits, 1);
      expect(attack.result.targetEliminated, isTrue);
      expect(attack.state.enemies, isEmpty);
    });

    test('guaranteed miss does no damage', () {
      final rules = CombatRules(rng: _FixedRng(1));
      final initialState = _state(
        players: [_player()],
        enemies: [_enemyInst(instanceId: 'e1', hp: 2)],
      );
      final attack = rules.playerAttack(initialState, 'p1', 'e1', _enemyDef(hp: 2), diceCount: 2);

      expect(attack.result.hits, 0);
      expect(attack.result.targetEliminated, isFalse);
      expect(attack.state.enemies.first.currentHp, 2);
    });

    test('armor reduces effective damage', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final initialState = _state(
        players: [_player()],
        enemies: [_enemyInst(instanceId: 'e1', hp: 5)],
      );
      final attack = rules.playerAttack(
        initialState, 'p1', 'e1', _enemyDef(hp: 5, abilities: ['armor_2']),
        diceCount: 2,
      );
      // 2 hits - 2 armor = 0 effective damage.
      expect(attack.result.damageDealt, 0);
      expect(attack.state.enemies.first.currentHp, 5);
    });

    test('killing an enemy grants xp to attacker', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final initialState = _state(
        players: [_player(xp: 0)],
        enemies: [_enemyInst(hp: 1)],
      );
      final attack = rules.playerAttack(initialState, 'p1', 'e1', _enemyDef(), diceCount: 1);

      expect(attack.result.xpGained, 1);
      expect(attack.state.players.first.xp, 1);
    });

    test('killing abomination grants 5 xp', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final initialState = _state(
        players: [_player(xp: 0)],
        enemies: [_enemyInst(hp: 1)],
      );
      final attack = rules.playerAttack(
        initialState, 'p1', 'e1', _enemyDef(tier: EnemyTier.abomination), diceCount: 1,
      );
      expect(attack.result.xpGained, 5);
    });

    test('attack consumes 1 action', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final initialState = _state(players: [_player(actions: 3)], enemies: [_enemyInst()]);
      final attack = rules.playerAttack(initialState, 'p1', 'e1', _enemyDef());
      expect(attack.state.players.first.actionsRemaining, 2);
    });

    test('enemy attack advances player danger level', () {
      final rules = CombatRules();
      final initialState = _state(
        players: [_player(danger: DangerLevel.blue)],
        enemies: [_enemyInst(x: 5, y: 6)],
      );
      final attack = rules.enemyAttack(initialState, initialState.enemies.first, _enemyDef(damage: 1));
      expect(attack.state.players.first.dangerLevel, DangerLevel.yellow);
    });

    test('enemy attack eliminates player already at red', () {
      final rules = CombatRules();
      final initialState = _state(
        players: [_player(danger: DangerLevel.red)],
        enemies: [_enemyInst(x: 5, y: 6)],
      );
      final attack = rules.enemyAttack(initialState, initialState.enemies.first, _enemyDef());
      expect(attack.state.players.first.isEliminated, isTrue);
    });
  });

  // ---- AlertSystem ----

  group('AlertSystem', () {
    final alert = AlertSystem();

    test('increments alert level by 1', () {
      final result = alert.increment(_state(alertLevel: 3), _mission());
      expect(result.state.alertLevel, 4);
    });

    test('does not exceed maxAlertLevel', () {
      final result = alert.increment(_state(alertLevel: 9), _mission(maxAlertLevel: 10), amount: 5);
      expect(result.state.alertLevel, 10);
    });

    test('sets defeat when maxAlertLevel reached', () {
      final result = alert.increment(_state(alertLevel: 9), _mission(maxAlertLevel: 10));
      expect(result.state.outcome, GameOutcome.defeat);
    });

    test('triggers events at correct threshold', () {
      final mission = _mission(
        alertEvents: [
          AlertEvent(
            triggerAlertLevel: 5,
            description: 'Wave incoming',
            eventType: 'spawn_wave',
            params: {},
          ),
        ],
      );
      final result = alert.increment(_state(alertLevel: 4), mission);
      expect(result.triggered, hasLength(1));
      expect(result.triggered.first.triggerAlertLevel, 5);
    });

    test('does not re-trigger events already passed', () {
      final mission = _mission(
        alertEvents: [
          AlertEvent(
            triggerAlertLevel: 5,
            description: 'Already passed',
            eventType: 'spawn_wave',
            params: {},
          ),
        ],
      );
      final result = alert.increment(_state(alertLevel: 6), mission);
      expect(result.triggered, isEmpty);
    });

    test('isAtOrAbove returns correct result', () {
      final state = _state(alertLevel: 7);
      expect(AlertSystem.isAtOrAbove(state, 7), isTrue);
      expect(AlertSystem.isAtOrAbove(state, 8), isFalse);
    });
  });

  // ---- SpawnSystem ----

  group('SpawnSystem', () {
    final catalog = _FakeCatalog({
      'drone_walker': _enemyDef(id: 'drone_walker', hp: 1),
      'infected_heavy': _enemyDef(id: 'infected_heavy', hp: 3),
    });
    final spawn = SpawnSystem(catalog: catalog);

    test('spawns enemies matching current alert level', () {
      final mission = _mission(
        spawnRules: [
          SpawnRule(alertLevel: 3, enemyId: 'drone_walker', count: 2, spawnPointId: 'sp1'),
        ],
      );
      final newState = spawn.spawnForAlertLevel(_state(alertLevel: 3), mission);
      expect(newState.enemies, hasLength(2));
      expect(newState.enemies.every((e) => e.definitionId == 'drone_walker'), isTrue);
    });

    test('does not spawn enemies for wrong alert level', () {
      final mission = _mission(
        spawnRules: [
          SpawnRule(alertLevel: 3, enemyId: 'drone_walker', count: 2, spawnPointId: 'sp1'),
        ],
      );
      final newState = spawn.spawnForAlertLevel(_state(alertLevel: 2), mission);
      expect(newState.enemies, isEmpty);
    });

    test('spawns from alert event', () {
      final event = AlertEvent(
        triggerAlertLevel: 5,
        description: 'Boss spawn',
        eventType: 'spawn_boss',
        params: {'enemyId': 'infected_heavy', 'count': 1, 'spawnPointId': 'sp1'},
      );
      final newState = spawn.spawnFromEvent(_state(), _mission(), event);
      expect(newState.enemies, hasLength(1));
      expect(newState.enemies.first.definitionId, 'infected_heavy');
      expect(newState.enemies.first.currentHp, 3);
    });

    test('new enemies have unique instance ids', () {
      final mission = _mission(
        spawnRules: [
          SpawnRule(alertLevel: 5, enemyId: 'drone_walker', count: 4, spawnPointId: 'sp1'),
        ],
      );
      final newState = spawn.spawnForAlertLevel(_state(alertLevel: 5), mission);
      final ids = newState.enemies.map((e) => e.instanceId).toSet();
      expect(ids.length, 4);
    });
  });
}

// ---- Test helpers ----

class _FixedRng implements Random {
  final int _value;
  const _FixedRng(this._value);

  @override
  int nextInt(int max) => (_value - 1).clamp(0, max - 1);
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => true;
}

class _FakeCatalog implements EnemyCatalogLookup {
  final Map<String, EnemyDefinition> _map;
  const _FakeCatalog(this._map);

  @override
  EnemyDefinition getById(String id) {
    final def = _map[id];
    if (def == null) throw ArgumentError('Unknown enemy: $id');
    return def;
  }
}
