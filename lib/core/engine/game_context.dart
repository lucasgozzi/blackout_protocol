import '../models/game_state.dart';
import '../models/player.dart';
import '../models/enemy.dart';
import '../models/mission.dart';

/// Defines a complete game state snapshot to jump into during development.
/// Use this to test specific scenarios without playing through from the start.
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
      sessionId:      'debug_session',
      missionId:      missionId,
      round:          round,
      phase:          phase,
      alertLevel:     alertLevel,
      players:        players,
      enemies:        enemies,
      objectives:     objectiveOverrides ?? [],
      activePlayerId: players.isNotEmpty ? players.first.playerId : '',
      outcome:        GameOutcome.none,
      eventLog:       ['[DEBUG] Context loaded: $missionId | Round $round | Alert $alertLevel'],
    );
  }
}

enum GameContextPreset {
  missionStart,   // Round 1, alert 0, clean state
  midMission,     // Round 5, alert 5, some enemies on board
  highAlert,      // Round 8, alert 8, crowded board
  bossEncounter,  // Abomination on board, low resources
  nearVictory,    // Objectives almost complete
  nearDefeat,     // All players damaged, high alert
}

abstract class GamePresets {
  static final Map<GameContextPreset, GameContext> _presets = {
    GameContextPreset.missionStart: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      1,
      alertLevel: 0,
      players:    [_fullHealthScout('zone_a'), _fullHealthEngineer('zone_b')],
      enemies:    [],
    ),

    GameContextPreset.midMission: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      5,
      alertLevel: 5,
      players:    [_fullHealthScout('zone_c'), _damagedEngineer('zone_d')],
      enemies:    [
        _enemy('drone_walker', 'e1', 'zone_f'),
        _enemy('drone_walker', 'e2', 'zone_g'),
        _enemy('drone_fatty',  'e3', 'zone_h'),
        _enemy('drone_runner', 'e4', 'zone_i'),
      ],
    ),

    GameContextPreset.bossEncounter: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      8,
      alertLevel: 8,
      players:    [_damagedScout('zone_b'), _damagedEngineer('zone_c')],
      enemies:    [
        _enemy('drone_abomination', 'boss', 'zone_g', currentHp: 10),
        _enemy('drone_runner', 'e1', 'zone_f'),
        _enemy('drone_runner', 'e2', 'zone_e'),
        _enemy('drone_fatty',  'e3', 'zone_h'),
      ],
    ),

    GameContextPreset.highAlert: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      9,
      alertLevel: 9,
      players:    [_fullHealthScout('zone_a'), _fullHealthEngineer('zone_b')],
      enemies:    [
        _enemy('drone_walker', 'e1', 'zone_d'),
        _enemy('drone_walker', 'e2', 'zone_e'),
        _enemy('drone_runner', 'e3', 'zone_f'),
        _enemy('drone_walker', 'e4', 'zone_g'),
        _enemy('drone_walker', 'e5', 'zone_h'),
        _enemy('drone_fatty',  'e6', 'zone_i'),
        _enemy('drone_runner', 'e7', 'zone_j'),
      ],
    ),

    GameContextPreset.nearVictory: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      6,
      alertLevel: 4,
      players:    [
        _playerWithXP('scout_1', 'scout_aria', 'zone_k', xp: 15,
            equippedLeft: 'fuel_canister', backpack: ['fuel_canister']),
        _playerWithXP('eng_1', 'engineer_rex', 'zone_k', xp: 10,
            equippedLeft: 'fuel_canister'),
      ],
      enemies: [
        _enemy('drone_walker', 'e1', 'zone_b'),
      ],
      objectiveOverrides: [
        Objective(
          id:          'obj_collect_fuel',
          description: 'Colete 3 canisters de combustível',
          type:        ObjectiveType.collect,
          isPrimary:   true,
          isCompleted: false,
          params:      {'itemId': 'fuel_canister', 'requiredCount': 3, 'currentCount': 3},
        ),
        Objective(
          id:          'obj_escape',
          description: 'Evacue todos os operadores pela zona de extração',
          type:        ObjectiveType.reach,
          isPrimary:   true,
          isCompleted: false,
          params:      {'targetTileTag': 'extraction_zone', 'requireAllPlayers': true},
        ),
      ],
    ),

    GameContextPreset.nearDefeat: GameContext(
      missionId:  'c01_m01_fuel_depot',
      round:      10,
      alertLevel: 9,
      players:    [
        _criticalPlayer('scout_1', 'scout_aria', 'zone_a'),
        _criticalPlayer('eng_1', 'engineer_rex', 'zone_a'),
      ],
      enemies: [
        _enemy('drone_abomination', 'boss', 'zone_c', currentHp: 6),
        _enemy('drone_runner',     'e1',   'zone_b'),
        _enemy('drone_runner',     'e2',   'zone_b'),
        _enemy('drone_fatty',      'e3',   'zone_c'),
      ],
    ),
  };

  // ---- Player builders ----

  static PlayerState _fullHealthScout(String zoneId) => PlayerState(
    playerId:         'scout_1',
    definitionId:     'scout_aria',
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               0,
    dangerLevel:      DangerLevel.blue,
    equippedLeft:     'pistol',
    backpack:         ['medkit'],
  );

  static PlayerState _fullHealthEngineer(String zoneId) => PlayerState(
    playerId:         'eng_1',
    definitionId:     'engineer_rex',
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               0,
    dangerLevel:      DangerLevel.blue,
    equippedLeft:     'pistol',
    backpack:         ['emp_grenade'],
  );

  static PlayerState _damagedScout(String zoneId) => PlayerState(
    playerId:         'scout_1',
    definitionId:     'scout_aria',
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               8,
    dangerLevel:      DangerLevel.yellow,
    equippedLeft:     'pistol',
  );

  static PlayerState _damagedEngineer(String zoneId) => PlayerState(
    playerId:         'eng_1',
    definitionId:     'engineer_rex',
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               5,
    dangerLevel:      DangerLevel.yellow,
    backpack:         [],
  );

  static PlayerState _criticalPlayer(String id, String defId, String zoneId) => PlayerState(
    playerId:         id,
    definitionId:     defId,
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               35,
    dangerLevel:      DangerLevel.orange,
    backpack:         [],
  );

  static PlayerState _playerWithXP(
    String id,
    String defId,
    String zoneId, {
    required int xp,
    String? equippedLeft,
    String? equippedRight,
    List<String> backpack = const [],
  }) => PlayerState(
    playerId:         id,
    definitionId:     defId,
    zoneId:           zoneId,
    actionsRemaining: 3,
    xp:               xp,
    dangerLevel:      xp >= 19
        ? DangerLevel.orange
        : xp >= 7
            ? DangerLevel.yellow
            : DangerLevel.blue,
    equippedLeft:  equippedLeft,
    equippedRight: equippedRight,
    backpack:      backpack,
  );

  // ---- Enemy builder ----

  static EnemyInstance _enemy(
    String definitionId,
    String instanceId,
    String zoneId, {
    int currentHp = 1,
  }) => EnemyInstance(
    instanceId:   instanceId,
    definitionId: definitionId,
    currentHp:    currentHp,
    zoneId:       zoneId,
  );
}
