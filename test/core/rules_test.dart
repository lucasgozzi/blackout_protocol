import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_protocol/core/models/game_state.dart';
import 'package:blackout_protocol/core/models/player.dart';
import 'package:blackout_protocol/core/models/enemy.dart';
import 'package:blackout_protocol/core/models/mission.dart';
import 'package:blackout_protocol/core/models/weapon.dart';
import 'package:blackout_protocol/core/rules/movement_rules.dart';
import 'package:blackout_protocol/core/rules/combat_rules.dart';
import 'package:blackout_protocol/core/rules/alert_system.dart';
import 'package:blackout_protocol/core/rules/spawn_system.dart';

// ---- Test fixtures ----

PlayerState _player({
  String id = 'p1',
  String defId = 'scout_aria',
  String zoneId = 'zone_a',
  int actions = 3,
  int xp = 0,
  DangerLevel danger = DangerLevel.blue,
  bool eliminated = false,
  int health = 2,
  int movementRange = 3,
}) =>
    PlayerState(
      playerId: id,
      definitionId: defId,
      zoneId: zoneId,
      actionsRemaining: actions,
      xp: xp,
      dangerLevel: danger,
      isEliminated: eliminated,
      health: health,
      movementRange: movementRange,
    );

WeaponDefinition _weapon({
  int dice = 1, int hitValue = 4, int damage = 1, bool canHurtAbomination = false,
}) =>
    WeaponDefinition(
      id: 'test_gun', name: 'Test', type: WeaponType.melee,
      minRange: 0, maxRange: 2, dice: dice, hitValue: hitValue, damage: damage,
      hands: 1, isNoisy: false, isConsumable: false,
      canHurtAbomination: canHurtAbomination,
    );

EnemyInstance _enemyInst({
  String instanceId = 'e1',
  String defId = 'drone_walker',
  String zoneId = 'zone_b',
  int hp = 1,
}) =>
    EnemyInstance(instanceId: instanceId, definitionId: defId, currentHp: hp, zoneId: zoneId);

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

// Minimal zone-graph stub for MovementRules tests.
// Provides a simple linear chain: zone_a — zone_b — zone_c — zone_d.
class _FakeMapData {
  static const _adj = <String, List<String>>{
    'zone_a': ['zone_b'],
    'zone_b': ['zone_a', 'zone_c'],
    'zone_c': ['zone_b', 'zone_d'],
    'zone_d': ['zone_c'],
  };

  List<_FakeZoneRef> adjacentZones(String zoneId, {dynamic openDoorKeys}) {
    return (_adj[zoneId] ?? []).map((id) => _FakeZoneRef(id)).toList();
  }
}

class _FakeZoneRef {
  final _FakeZone zone;
  _FakeZoneRef(String id) : zone = _FakeZone(id);
}

class _FakeZone {
  final String id;
  _FakeZone(this.id);
}

// ---- MovementRules ----

void main() {
  group('MovementRules', () {
    final map = _FakeMapData();

    test('returns empty when player has no actions', () {
      final p = _player(actions: 0, zoneId: 'zone_b');
      final result = MovementRules.reachableZones(p, map);
      expect(result, isEmpty);
    });

    test('player with 1 action reaches direct neighbours only', () {
      final p = _player(zoneId: 'zone_b', actions: 1, movementRange: 1);
      final result = MovementRules.reachableZones(p, map);
      expect(result, containsAll(['zone_a', 'zone_c']));
      expect(result.length, 2);
    });

    test('player with 2 actions reaches 2 hops', () {
      final p = _player(zoneId: 'zone_b', actions: 2);
      final result = MovementRules.reachableZones(p, map);
      expect(result.contains('zone_d'), isTrue);
    });

    test('canAttack returns true for same zone', () {
      final p = _player(zoneId: 'zone_a', actions: 1);
      expect(MovementRules.canAttack(p, 'zone_a', map, range: 1), isTrue);
    });

    test('canAttack returns true for adjacent zone', () {
      final p = _player(zoneId: 'zone_b', actions: 1);
      expect(MovementRules.canAttack(p, 'zone_c', map, range: 1), isTrue);
    });

    test('canAttack returns false for zone 3 hops away with range 1', () {
      final p = _player(zoneId: 'zone_a', actions: 1);
      expect(MovementRules.canAttack(p, 'zone_d', map, range: 1), isFalse);
    });

    test('canAttack returns false with no actions remaining', () {
      final p = _player(zoneId: 'zone_b', actions: 0);
      expect(MovementRules.canAttack(p, 'zone_c', map, range: 1), isFalse);
    });

    test('attackableZones includes direct neighbours but not current zone', () {
      final p = _player(zoneId: 'zone_b', actions: 1);
      final zones = MovementRules.attackableZones(p, map, range: 1);
      expect(zones, containsAll(['zone_a', 'zone_c']));
      expect(zones.contains('zone_b'), isFalse);
    });
  });

  // ---- CombatRules ----

  group('CombatRules', () {
    test('guaranteed hit kills walker (hp=1)', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final state = _state(
        players: [_player()],
        enemies: [_enemyInst(instanceId: 'e1', hp: 1, zoneId: 'zone_b')],
      );
      final result = rules.attackZone(state, 'p1', _weapon(), 'zone_b');

      expect(result.log.hits, 1);
      expect(result.log.eliminatedEnemyIds, contains('e1'));
      expect(result.state.enemies, isEmpty);
    });

    test('guaranteed miss does no damage', () {
      final rules = CombatRules(rng: _FixedRng(1));
      final state = _state(
        players: [_player()],
        enemies: [_enemyInst(instanceId: 'e1', hp: 2, zoneId: 'zone_b')],
      );
      final result = rules.attackZone(state, 'p1', _weapon(dice: 2), 'zone_b');

      expect(result.log.hits, 0);
      expect(result.log.eliminatedEnemyIds, isEmpty);
      expect(result.state.enemies.first.currentHp, 2);
    });

    test('killing an enemy grants xp to attacker', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final state = _state(
        players: [_player(xp: 0)],
        enemies: [_enemyInst(hp: 1, zoneId: 'zone_b')],
      );
      final result = rules.attackZone(state, 'p1', _weapon(), 'zone_b');

      expect(result.log.xpGained, 1);
      expect(result.state.players.first.xp, 1);
    });

    test('killing abomination grants 5 xp', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final state = _state(
        players: [_player(xp: 0)],
        enemies: [_enemyInst(defId: 'drone_abomination', hp: 1, zoneId: 'zone_b')],
      );
      final result = rules.attackZone(state, 'p1', _weapon(canHurtAbomination: true, damage: 999), 'zone_b');

      expect(result.log.xpGained, 5);
    });

    test('attack consumes 1 action', () {
      final rules = CombatRules(rng: _FixedRng(6));
      final state = _state(players: [_player(actions: 3)], enemies: [_enemyInst(zoneId: 'zone_b')]);
      final result = rules.attackZone(state, 'p1', _weapon(), 'zone_b');

      expect(result.state.players.first.actionsRemaining, 2);
    });

    test('enemy attack reduces player health by 1', () {
      final rules = CombatRules();
      final player = _player(health: 2);
      final state  = _state(players: [player], enemies: [_enemyInst(zoneId: 'zone_b')]);
      final after  = rules.enemyAttackPlayer(state, state.enemies.first, _enemyDef(damage: 1), player);

      expect(after.players.first.health, 1);
      expect(after.players.first.isEliminated, isFalse);
    });

    test('enemy attack eliminates player at 1 health', () {
      final rules = CombatRules();
      final player = _player(health: 1);
      final state  = _state(players: [player], enemies: [_enemyInst(zoneId: 'zone_b')]);
      final after  = rules.enemyAttackPlayer(state, state.enemies.first, _enemyDef(), player);

      expect(after.players.first.health, 0);
      expect(after.players.first.isEliminated, isTrue);
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
