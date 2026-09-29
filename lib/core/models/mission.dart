import 'package:freezed_annotation/freezed_annotation.dart';

part 'mission.freezed.dart';
part 'mission.g.dart';

enum ObjectiveType { collect, rescue, disable, reach, eliminate, survive }

@freezed
class Objective with _$Objective {
  const factory Objective({
    required String id,
    required String description,
    required ObjectiveType type,
    required bool isPrimary,
    required Map<String, dynamic> params, // flexible per objective type
    @Default(false) bool isCompleted,
  }) = _Objective;

  factory Objective.fromJson(Map<String, dynamic> json) =>
      _$ObjectiveFromJson(json);
}

@freezed
class SpawnPoint with _$SpawnPoint {
  const factory SpawnPoint({
    required String id,
    required int x,
    required int y,
    required String direction, // N, S, E, W
  }) = _SpawnPoint;

  factory SpawnPoint.fromJson(Map<String, dynamic> json) =>
      _$SpawnPointFromJson(json);
}

@freezed
class SpawnRule with _$SpawnRule {
  const factory SpawnRule({
    required int alertLevel,      // triggers at this alert level
    required String enemyId,
    required int count,
    required String spawnPointId, // which spawn point to use
  }) = _SpawnRule;

  factory SpawnRule.fromJson(Map<String, dynamic> json) =>
      _$SpawnRuleFromJson(json);
}

@freezed
class AlertEvent with _$AlertEvent {
  const factory AlertEvent({
    required int triggerAlertLevel,
    required String description,
    required String eventType,            // spawn_wave, activate_trap, etc.
    required Map<String, dynamic> params,
  }) = _AlertEvent;

  factory AlertEvent.fromJson(Map<String, dynamic> json) =>
      _$AlertEventFromJson(json);
}

@freezed
class MissionDefinition with _$MissionDefinition {
  const factory MissionDefinition({
    required String id,
    required String campaignId,
    required int missionNumber,
    required String title,
    required String description,
    required String mapAsset,             // path to Tiled .tmj file
    required int maxAlertLevel,           // spawn escalation cap (not a defeat condition)
    required int maxRounds,               // optional round limit (0 = unlimited)
    required List<Objective> objectives,
    required List<SpawnPoint> spawnPoints,
    required List<SpawnRule> spawnRules,
    required List<AlertEvent> alertEvents,
    required List<String> availablePlayers,
    required Map<String, int> startingItems, // itemId -> quantity
    @Default([]) List<String> requiredCompletedMissions,
    // Optional custom spawn deck — list of {type, count, enemyId} objects.
    // If absent, falls back to SpawnDeck.campaign01().
    @Default([]) List<Map<String, dynamic>> spawnDeck,
    // Tutorial hints — list of {id, trigger, title, message} objects.
    // Only present in tutorial missions. Empty = no tutorial.
    @Default([]) List<Map<String, dynamic>> tutorialHints,
  }) = _MissionDefinition;

  factory MissionDefinition.fromJson(Map<String, dynamic> json) =>
      _$MissionDefinitionFromJson(json);
}
