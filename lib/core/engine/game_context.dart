import '../models/game_state.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/mission.dart';

/// Defines a complete game state snapshot to jump into during development.
/// Use this to test specific scenarios without playing through from the start.
///
/// Usage:
///   final ctx = GameContext.preset(GamePresets.bossEncounter);
///   // or
///   final ctx = GameContext(
///     missionId: 'c01_m01_fuel_depot',
///     round: 5,
///     alertLevel: 7,
///     players: [...],
///     enemies: [...],
///   );
class GameContext {
  final String missionId;
  final int round;
  final int alertLevel;
  final GamePhase phase;
  final List<PlayerState> players;
  final List<EnemyInstance> enemies;
  final List<Objective>? objectiveOverrides;

  const GameContext({
    required this.missionId,
    required this.round,
    required this.alertLevel,
    this.phase = GamePhase.playerTurn,
    required this.players,
    required this.enemies,
    this.objectiveOverrides,
  });

  factory GameContext.preset(GameContextPreset preset) =>
      GamePresets._presets[preset]!;

  GameState toGameState() {
    return GameState(
      sessionId: 'debug_session',
      missionId: missionId,
      round: round,
      phase: phase,
      alertLevel: alertLevel,
      players: players,
      enemies: enemies,
      objectives: objectiveOverrides ?? [],
      activePlayerId: players.isNotEmpty ? players.first.playerId : '',
      outcome: GameOutcome.none,
      eventLog: ['[DEBUG] Context loaded: $missionId | Round $round | Alert $alertLevel'],
    );
  }
}

enum GameContextPreset {
  missionStart,      // Round 1, alert 0, clean state
  midMission,        // Round 5, alert 5, some enemies on board
  highAlert,         // Round 8, alert 8, crowded board
  bossEncounter,     // SENTINEL-9 on board, low resources
  nearVictory,       // Objectives almost complete
  nearDefeat,        // All players damaged, high alert
}

abstract class GamePresets {
  static final Map<GameContextPreset, GameContext> _presets = {
    GameContextPreset.missionStart: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 1,
      alertLevel: 0,
      players: [_fullHealthScout(x: 5, y: 5), _fullHealthEngineer(x: 5, y: 6)],
      enemies: [],
    ),

    GameContextPreset.midMission: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 5,
      alertLevel: 5,
      players: [_fullHealthScout(x: 4, y: 4), _damagedEngineer(x: 3, y: 4)],
      enemies: [
        _enemy('drone_walker', 'e1', x: 7, y: 3),
        _enemy('drone_walker', 'e2', x: 8, y: 4),
        _enemy('infected_walker', 'e3', x: 2, y: 8),
        _enemy('security_walker', 'e4', x: 9, y: 6),
      ],
    ),

    GameContextPreset.bossEncounter: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 8,
      alertLevel: 8,
      players: [
        _damagedScout(x: 3, y: 3),
        _damagedEngineer(x: 4, y: 3),
      ],
      enemies: [
        _enemy('security_abomination', 'boss', x: 8, y: 5, currentHp: 10),
        _enemy('drone_runner', 'e1', x: 6, y: 4),
        _enemy('drone_runner', 'e2', x: 7, y: 3),
        _enemy('infected_heavy', 'e3', x: 5, y: 7),
      ],
    ),

    GameContextPreset.highAlert: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 9,
      alertLevel: 9,
      players: [_fullHealthScout(x: 2, y: 2), _fullHealthEngineer(x: 2, y: 3)],
      enemies: [
        _enemy('drone_walker', 'e1', x: 5, y: 2),
        _enemy('drone_walker', 'e2', x: 6, y: 3),
        _enemy('drone_runner', 'e3', x: 7, y: 5),
        _enemy('infected_walker', 'e4', x: 3, y: 8),
        _enemy('infected_walker', 'e5', x: 4, y: 7),
        _enemy('infected_heavy', 'e6', x: 8, y: 2),
        _enemy('security_walker', 'e7', x: 9, y: 4),
      ],
    ),

    GameContextPreset.nearVictory: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 6,
      alertLevel: 4,
      players: [
        _playerWithXP('scout_1', 'scout_aria', x: 9, y: 9, xp: 15, equippedLeft: 'fuel_canister', backpack: ['fuel_canister']),
        _playerWithXP('eng_1', 'engineer_rex', x: 9, y: 8, xp: 10, equippedLeft: 'fuel_canister'),
      ],
      enemies: [
        _enemy('drone_walker', 'e1', x: 3, y: 3),
      ],
      objectiveOverrides: [
        Objective(
          id: 'obj_collect_fuel',
          description: 'Colete 3 canisters de combustível',
          type: ObjectiveType.collect,
          isPrimary: true,
          isCompleted: false,
          params: {'itemId': 'fuel_canister', 'requiredCount': 3, 'currentCount': 3},
        ),
        Objective(
          id: 'obj_escape',
          description: 'Evacue todos os operadores pela zona de extração',
          type: ObjectiveType.reach,
          isPrimary: true,
          isCompleted: false,
          params: {'targetTileTag': 'extraction_zone', 'requireAllPlayers': true},
        ),
      ],
    ),

    GameContextPreset.nearDefeat: GameContext(
      missionId: 'c01_m01_fuel_depot',
      round: 10,
      alertLevel: 9,
      players: [
        _criticalPlayer('scout_1', 'scout_aria', x: 1, y: 1),
        _criticalPlayer('eng_1', 'engineer_rex', x: 1, y: 2),
      ],
      enemies: [
        _enemy('security_abomination', 'boss', x: 4, y: 4, currentHp: 6),
        _enemy('drone_runner', 'e1', x: 2, y: 3),
        _enemy('drone_runner', 'e2', x: 3, y: 2),
        _enemy('infected_heavy', 'e3', x: 3, y: 3),
      ],
    ),
  };

  // ---- Player builders ----

  static PlayerState _fullHealthScout({required int x, required int y}) =>
      PlayerState(
        playerId: 'scout_1',
        definitionId: 'scout_aria',
        x: x, y: y,
        actionsRemaining: 3,
        xp: 0,
        dangerLevel: DangerLevel.blue,
        equippedLeft: 'pistol', backpack: ['medkit'],
      );

  static PlayerState _fullHealthEngineer({required int x, required int y}) =>
      PlayerState(
        playerId: 'eng_1',
        definitionId: 'engineer_rex',
        x: x, y: y,
        actionsRemaining: 3,
        xp: 0,
        dangerLevel: DangerLevel.blue,
        equippedLeft: 'pistol', backpack: ['emp_grenade'],
      );

  static PlayerState _damagedScout({required int x, required int y}) =>
      PlayerState(
        playerId: 'scout_1',
        definitionId: 'scout_aria',
        x: x, y: y,
        actionsRemaining: 3,
        xp: 8,
        dangerLevel: DangerLevel.yellow,
        equippedLeft: 'pistol',
      );

  static PlayerState _damagedEngineer({required int x, required int y}) =>
      PlayerState(
        playerId: 'eng_1',
        definitionId: 'engineer_rex',
        x: x, y: y,
        actionsRemaining: 3,
        xp: 5,
        dangerLevel: DangerLevel.yellow,
        backpack: [],
      );

  static PlayerState _criticalPlayer(String id, String defId, {required int x, required int y}) =>
      PlayerState(
        playerId: id,
        definitionId: defId,
        x: x, y: y,
        actionsRemaining: 3,
        xp: 35,
        dangerLevel: DangerLevel.orange,
        backpack: [],
      );

  static PlayerState _playerWithXP(
    String id,
    String defId, {
    required int x,
    required int y,
    required int xp,
    String? equippedLeft,
    String? equippedRight,
    List<String> backpack = const [],
  }) =>
      PlayerState(
        playerId: id,
        definitionId: defId,
        x: x, y: y,
        actionsRemaining: 3,
        xp: xp,
        dangerLevel: xp >= 19
            ? DangerLevel.orange
            : xp >= 7
                ? DangerLevel.yellow
                : DangerLevel.blue,
        equippedLeft: equippedLeft,
        equippedRight: equippedRight,
        backpack: backpack,
      );

  // ---- Enemy builder ----

  static EnemyInstance _enemy(
    String definitionId,
    String instanceId, {
    required int x,
    required int y,
    int currentHp = 1,
  }) =>
      EnemyInstance(
        instanceId: instanceId,
        definitionId: definitionId,
        currentHp: currentHp,
        x: x,
        y: y,
      );
}
