import 'package:freezed_annotation/freezed_annotation.dart';

part 'player.freezed.dart';
part 'player.g.dart';

enum PlayerRole { scout, engineer, medic, soldier }

@freezed
class PlayerDefinition with _$PlayerDefinition {
  const factory PlayerDefinition({
    required String id,
    required String name,
    required PlayerRole role,
    required String spriteId,
    required String description,
    required List<String> startingAbilities,
    @Default([7, 19, 43]) List<int> xpThresholds,
    @Default(3) int movementRange,
    @Default('pistol') String startingWeapon,
  }) = _PlayerDefinition;

  factory PlayerDefinition.fromJson(Map<String, dynamic> json) =>
      _$PlayerDefinitionFromJson(json);
}

enum DangerLevel { blue, yellow, orange, red }

/// Zombicide-style inventory:
/// - 2 hand slots (equippedLeft / equippedRight)
/// - 3 backpack slots
/// - Total capacity = 5 items
@freezed
class PlayerState with _$PlayerState {
  const factory PlayerState({
    required String playerId,
    required String definitionId,
    @Default('') String zoneId,
    required int actionsRemaining,
    required int xp,
    required DangerLevel dangerLevel,
    @Default(3) int movementRange,
    @Default(0) int zonesMovedThisTurn,
    // Inventory — hand slots hold weapon ids, null = empty
    @Default(null) String? equippedLeft,
    @Default(null) String? equippedRight,
    @Default([]) List<String> backpack,   // max 3 items
    @Default([]) List<String> unlockedAbilities,
    @Default(false) bool isEliminated,
    @Default(false) bool hasArmorVest,
    // Health is tracked separately from dangerLevel (which is XP-based progression only).
    @Default(2) int health,
    @Default(false) bool resistanceUsedThisTurn,
  }) = _PlayerState;

  factory PlayerState.fromJson(Map<String, dynamic> json) =>
      _$PlayerStateFromJson(json);
}

extension PlayerStateX on PlayerState {
  int get actionsPerTurn => 3;

  DangerLevel get currentDangerLevel {
    if (xp >= 43) return DangerLevel.red;
    if (xp >= 19) return DangerLevel.orange;
    if (xp >= 7)  return DangerLevel.yellow;
    return DangerLevel.blue;
  }

  int get inventoryCount =>
      (equippedLeft  != null ? 1 : 0) +
      (equippedRight != null ? 1 : 0) +
      backpack.length;

  bool get inventoryFull => inventoryCount >= 5;

  List<String> get allItems => [
    if (equippedLeft  != null) equippedLeft!,
    if (equippedRight != null) equippedRight!,
    ...backpack,
  ];

  /// Returns the best weapon for a given attack distance.
  /// Prefers equipped weapons that can reach the distance.
  String? bestWeaponFor(int distance) {
    // Check equipped weapons first.
    if (equippedLeft  != null) return equippedLeft;
    if (equippedRight != null) return equippedRight;
    // Fall back to fists.
    return null;
  }

  /// Both equipped weapons for the attack UI.
  List<String> get equippedWeapons => [
    if (equippedLeft  != null) equippedLeft!,
    if (equippedRight != null) equippedRight!,
  ];
}
