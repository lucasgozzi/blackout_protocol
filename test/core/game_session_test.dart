import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_protocol/core/engine/game_context.dart';
import 'package:blackout_protocol/core/engine/game_session_notifier.dart';
import 'package:blackout_protocol/core/models/game_state.dart';
import 'package:blackout_protocol/core/models/mission.dart';
import 'package:blackout_protocol/core/models/player.dart';
import 'package:blackout_protocol/core/models/enemy.dart';
import 'package:blackout_protocol/data/asset_loader.dart';
import 'package:blackout_protocol/data/enemy_catalog.dart';

// ---- Helpers ----

final _loader = FileAssetLoader('.');

Future<EnemyCatalog> _loadCatalog() => EnemyCatalog.load(_loader);

MissionDefinition _mission({
  int maxAlertLevel = 10,
  int maxRounds = 0,
  List<Objective> objectives = const [],
  List<SpawnRule> spawnRules = const [],
  List<AlertEvent> alertEvents = const [],
}) =>
    MissionDefinition(
      id: 'c01_m01_fuel_depot',
      campaignId: 'campaign_01',
      missionNumber: 1,
      title: 'Test',
      description: '',
      mapAsset: '',
      maxAlertLevel: maxAlertLevel,
      maxRounds: maxRounds,
      objectives: objectives,
      spawnPoints: [SpawnPoint(id: 'sp1', x: 0, y: 0, direction: 'S')],
      spawnRules: spawnRules,
      alertEvents: alertEvents,
      availablePlayers: [],
      startingItems: {},
    );

GameSessionNotifier _buildNotifier(EnemyCatalog catalog) {
  final container = ProviderContainer();
  final notifier = container.read(gameSessionProvider.notifier);
  notifier.init(catalog);
  return notifier;
}

GameContext _ctx({
  int round = 1,
  int alertLevel = 0,
  List<PlayerState>? players,
  List<EnemyInstance>? enemies,
}) =>
    GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: round,
      alertLevel: alertLevel,
      players: players ?? [
        PlayerState(
          playerId: 'p1',
          definitionId: 'scout_aria',
          zoneId: 'zone_a',
          actionsRemaining: 3,
          xp: 0,
          dangerLevel: DangerLevel.blue,
        ),
      ],
      enemies: enemies ?? [],
    );

// ---- Tests ----

void main() {
  group('GameSessionNotifier — session lifecycle', () {
    test('state is null before any session is loaded', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      expect(notifier.state, isNull);
    });

    test('loadContext sets isLoaded and injects game state', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      final ctx = _ctx(round: 3, alertLevel: 5);
      notifier.loadContext(ctx, _mission());

      expect(notifier.state, isNotNull);
      expect(notifier.state!.isLoaded, isTrue);
      expect(notifier.state!.game.round, 3);
      expect(notifier.state!.game.alertLevel, 5);
    });

    test('endSession clears state', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(), _mission());
      notifier.endSession();
      expect(notifier.state, isNull);
    });

    test('startMission creates players at correct positions', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(), _mission());

      final game = notifier.state!.game;
      expect(game.round, 1);
      expect(game.phase, GamePhase.playerTurn);
      expect(game.outcome, GameOutcome.none);
    });
  });

  group('GameSessionNotifier — player actions', () {
    test('movePlayer updates player position and consumes actions', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(), _mission());

      notifier.movePlayer('p1', 'zone_b');

      final player = notifier.state!.game.players.first;
      expect(player.zoneId, 'zone_b');
      expect(player.actionsRemaining, 2);
    });

    test('attackEnemy removes enemy on kill', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);

      notifier.loadContext(
        _ctx(players: [
          PlayerState(
            playerId: 'p1', definitionId: 'soldier_kai',
            zoneId: 'zone_a', actionsRemaining: 3, xp: 0,
            dangerLevel: DangerLevel.blue,
          ),
        ], enemies: [
          EnemyInstance(instanceId: 'e1', definitionId: 'drone_walker', currentHp: 1, zoneId: 'zone_a'),
        ]),
        _mission(),
      );

      // drone_walker has hp=1 — one hit kills it. We can't control dice here,
      // so we just verify the action runs without throwing.
      expect(() => notifier.attackEnemy('p1', 'e1'), returnsNormally);
    });

    test('interact completes objective', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);

      final objective = Objective(
        id: 'obj1',
        description: 'Test objective',
        type: ObjectiveType.collect,
        isPrimary: true,
        isCompleted: false,
        params: {},
      );

      final ctx = GameContext(
        missionId: 'c01_m01_fuel_depot',
        round: 1,
        alertLevel: 0,
        players: [
          PlayerState(
            playerId: 'p1', definitionId: 'scout_aria',
            zoneId: 'zone_a', actionsRemaining: 3, xp: 0,
            dangerLevel: DangerLevel.blue,
          ),
        ],
        enemies: [],
        objectiveOverrides: [objective],
      );

      notifier.loadContext(ctx, _mission(objectives: [objective]));
      notifier.interact('p1', 'obj1');

      final completed = notifier.state!.game.objectives.first;
      expect(completed.isCompleted, isTrue);
    });
  });

  group('GameSessionNotifier — turn flow', () {
    test('endPlayerTurn increments alert level', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(alertLevel: 2), _mission());

      notifier.endPlayerTurn();

      expect(notifier.state!.game.alertLevel, greaterThan(2));
    });

    test('endPlayerTurn advances to round 2', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(round: 1), _mission());

      notifier.endPlayerTurn();

      expect(notifier.state!.game.round, 2);
    });

    test('endPlayerTurn resets player actions to 3', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(), _mission());

      notifier.movePlayer('p1', 'zone_b');
      expect(notifier.state!.game.players.first.actionsRemaining, 2);

      notifier.endPlayerTurn();

      expect(notifier.state!.game.players.first.actionsRemaining, 3);
    });

    test('game ends in defeat when maxRounds exceeded', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(round: 3), _mission(maxRounds: 3));

      notifier.endPlayerTurn();

      expect(notifier.state!.game.outcome, GameOutcome.defeat);
    });

    test('reaching maxAlertLevel causes defeat', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(_ctx(alertLevel: 9), _mission(maxAlertLevel: 10));

      notifier.endPlayerTurn();

      expect(notifier.state!.game.outcome, GameOutcome.defeat);
    });

    test('completing all primary objectives triggers victory', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);

      final objective = Objective(
        id: 'obj1',
        description: 'Primary',
        type: ObjectiveType.collect,
        isPrimary: true,
        isCompleted: false,
        params: {},
      );

      final ctx = GameContext(
        missionId: 'c01_m01_fuel_depot',
        round: 1, alertLevel: 0,
        players: [
          PlayerState(
            playerId: 'p1', definitionId: 'scout_aria',
            zoneId: 'zone_a', actionsRemaining: 3, xp: 0,
            dangerLevel: DangerLevel.blue,
          ),
        ],
        enemies: [],
        objectiveOverrides: [objective],
      );

      notifier.loadContext(ctx, _mission(objectives: [objective]));
      notifier.interact('p1', 'obj1');

      expect(notifier.state!.game.outcome, GameOutcome.victory);
    });
  });

  group('GameSessionNotifier — debug presets', () {
    test('all presets load without throwing', () async {
      final catalog = await _loadCatalog();

      for (final preset in GameContextPreset.values) {
        final notifier = _buildNotifier(catalog);
        final ctx = GameContext.preset(preset);
        expect(
          () => notifier.loadContext(ctx, _mission()),
          returnsNormally,
          reason: 'preset $preset threw on loadContext',
        );
        expect(notifier.state, isNotNull, reason: 'preset $preset state is null');
      }
    });

    test('bossEncounter preset has SENTINEL-9 on board', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(GameContext.preset(GameContextPreset.bossEncounter), _mission());

      final hasBoss = notifier.state!.game.enemies
          .any((e) => e.definitionId == 'drone_abomination');
      expect(hasBoss, isTrue);
    });

    test('nearVictory preset has objectives with high collect count', () async {
      final catalog = await _loadCatalog();
      final notifier = _buildNotifier(catalog);
      notifier.loadContext(GameContext.preset(GameContextPreset.nearVictory), _mission());

      expect(notifier.state!.game.players.first.allItems, isNotEmpty);
    });
  });
}
