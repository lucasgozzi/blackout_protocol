import 'package:freezed_annotation/freezed_annotation.dart';

part 'enemy.freezed.dart';
part 'enemy.g.dart';

enum EnemyType { corruptedDrone }

enum EnemyTier { walker, runner, fatty, abomination }

@freezed
class EnemyDefinition with _$EnemyDefinition {
  const factory EnemyDefinition({
    required String id,
    required String name,
    required EnemyType type,
    required EnemyTier tier,
    required int hp,           // kept for compatibility, use damageToKill
    @Default(1) int damageToKill, // min weapon damage needed to kill this enemy
    required int damage,
    required int actions, // actions per activation
    required int activationPriority, // lower = activates first
    required String spriteId,
    @Default([]) List<String> specialAbilities,
  }) = _EnemyDefinition;

  factory EnemyDefinition.fromJson(Map<String, dynamic> json) =>
      _$EnemyDefinitionFromJson(json);
}

@freezed
class EnemyInstance with _$EnemyInstance {
  const factory EnemyInstance({
    required String instanceId,
    required String definitionId,
    required int currentHp,
    @Default('') String zoneId,
    @Default(false) bool activated,
  }) = _EnemyInstance;

  factory EnemyInstance.fromJson(Map<String, dynamic> json) =>
      _$EnemyInstanceFromJson(json);
}
