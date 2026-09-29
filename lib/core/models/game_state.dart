import 'package:freezed_annotation/freezed_annotation.dart';
import 'enemy.dart';
import 'player.dart';
import 'mission.dart';

part 'game_state.freezed.dart';
part 'game_state.g.dart';

enum GamePhase {
  playerTurn,
  enemyTurn,
  alertPhase,
  missionEnd,
}

enum GameOutcome { none, victory, defeat }

@freezed
class GameState with _$GameState {
  const factory GameState({
    required String sessionId,
    required String missionId,
    required int round,
    required GamePhase phase,
    required int alertLevel,
    required List<PlayerState> players,
    required List<EnemyInstance> enemies,
    required List<Objective> objectives,
    required String activePlayerId,
    required GameOutcome outcome,
    @Default([]) List<String> eventLog,
    // Noise tokens per zone — zoneId → noise count. Cleared after zombie phase.
    @Default({}) Map<String, int> noiseTokens,
    // Last combat result for UI feedback.
    @Default(null) ZoneCombatLog? lastCombatLog,
    // Set of "fromZoneId|toZoneId" keys for opened doors.
    @Default([]) List<String> openDoors,
    // Zone IDs that are active spawn points. Populated at mission start from MapData.
    @Default([]) List<String> spawnZones,
    // Pending spawn animations — stored as raw maps to avoid freezed issues.
    // Each map: {zoneId, zoneName, enemyId, enemyName, count, tier}
    @Default([]) List<Map<String, dynamic>> pendingSpawnMaps,
    // Set when an enemy wounds a player — cleared by UI after showing feedback.
    @Default(null) String? lastWoundedPlayerId,
    // Active traps — "x,y" → damage on trigger. Consumed on first enemy contact.
    @Default({}) Map<String, int> traps,
  }) = _GameState;

  factory GameState.fromJson(Map<String, dynamic> json) =>
      _$GameStateFromJson(json);
}

/// Logged after each zone attack — lets the HUD show dice results.
@freezed
class ZoneCombatLog with _$ZoneCombatLog {
  const factory ZoneCombatLog({
    required String attackerId,
    required String weaponId,
    required String targetZoneId,
    required List<int> rolls,
    required int hits,
    required int hitValue,
    required List<String> eliminatedEnemyIds,
    required List<String> woundedSurvivorIds,
    required int xpGained,
    required bool friendlyFire,
  }) = _ZoneCombatLog;

  factory ZoneCombatLog.fromJson(Map<String, dynamic> json) =>
      _$ZoneCombatLogFromJson(json);
}
