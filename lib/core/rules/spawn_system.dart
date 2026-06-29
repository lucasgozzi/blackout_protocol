import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/enemy.dart';
import '../models/mission.dart';

const _uuid = Uuid();

class SpawnSystem {
  final EnemyCatalogLookup catalog;

  const SpawnSystem({required this.catalog});

  /// Spawns enemies according to rules triggered at the current alert level.
  /// Called at the start of each Alert Phase.
  GameState spawnForAlertLevel(
    GameState state,
    MissionDefinition mission,
  ) {
    final rules = _rulesForLevel(state.alertLevel, mission);
    if (rules.isEmpty) return state;

    final newEnemies = <EnemyInstance>[];
    final logEntries = <String>[];

    for (final rule in rules) {
      final spawnPoint = _spawnPointById(rule.spawnPointId, mission);
      if (spawnPoint == null) continue;

      for (var i = 0; i < rule.count; i++) {
        final def = catalog.getById(rule.enemyId);
        final (spawnX, spawnY) = _resolveSpawnPosition(
          spawnPoint.x,
          spawnPoint.y,
          newEnemies + state.enemies,
          state,
        );
        newEnemies.add(EnemyInstance(
          instanceId: _uuid.v4(),
          definitionId: rule.enemyId,
          currentHp: def.hp,
          x: spawnX,
          y: spawnY,
        ));
      }

      logEntries.add('Spawned ${rule.count}x ${rule.enemyId} at ${rule.spawnPointId}');
    }

    return state.copyWith(
      enemies: [...state.enemies, ...newEnemies],
      eventLog: [...state.eventLog, ...logEntries].takeLast(20).toList(),
    );
  }

  /// Spawns enemies from a specific AlertEvent (boss spawns, wave events, etc.).
  GameState spawnFromEvent(
    GameState state,
    MissionDefinition mission,
    AlertEvent event,
  ) {
    if (event.eventType != 'spawn_wave' && event.eventType != 'spawn_boss') {
      return state;
    }

    final enemyId = event.params['enemyId'] as String;
    final count = event.params['count'] as int;
    final spawnPointId = event.params['spawnPointId'] as String;
    final spawnPoint = _spawnPointById(spawnPointId, mission);
    if (spawnPoint == null) return state;

    final newEnemies = <EnemyInstance>[];
    for (var i = 0; i < count; i++) {
      final def = catalog.getById(enemyId);
      final (spawnX, spawnY) = _resolveSpawnPosition(
        spawnPoint.x,
        spawnPoint.y,
        newEnemies + state.enemies,
        state,
      );
      newEnemies.add(EnemyInstance(
        instanceId: _uuid.v4(),
        definitionId: enemyId,
        currentHp: def.hp,
        x: spawnX,
        y: spawnY,
      ));
    }

    final log = '${event.description} — spawned ${count}x $enemyId';
    return state.copyWith(
      enemies: [...state.enemies, ...newEnemies],
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  /// Spawn enemies in a zone using world coords from GameState.spawnZoneCoords.
  GameState spawnInZone(
    GameState state,
    String zoneId,
    String enemyId,
    int count, {
    String zoneName = '',
  }) {
    final coordStr = state.spawnZoneCoords[zoneId];
    if (coordStr == null) return state;

    final parts = coordStr.split(',');
    final wx = int.tryParse(parts[0]) ?? 0;
    final wy = int.tryParse(parts[1]) ?? 0;

    final def = catalog.getById(enemyId);
    final newEnemies = <EnemyInstance>[];

    for (var i = 0; i < count; i++) {
      final (spawnX, spawnY) = _resolveSpawnPosition(
          wx, wy, newEnemies + state.enemies, state);
      newEnemies.add(EnemyInstance(
        instanceId:   _uuid.v4(),
        definitionId: enemyId,
        currentHp:    def.hp,
        x: spawnX,
        y: spawnY,
      ));
    }

    final spawnMap = <String, dynamic>{
      'zoneId':    zoneId,
      'zoneName':  zoneName.isEmpty ? zoneId : zoneName,
      'enemyId':   enemyId,
      'enemyName': def.name,
      'count':     count,
      'tier':      def.tier.name,
    };

    final log = 'SPAWN: ${count}× ${def.name} em $zoneId';
    return state.copyWith(
      enemies:         [...state.enemies, ...newEnemies],
      eventLog:        [...state.eventLog, log].takeLast(20).toList(),
      pendingSpawnMaps: [...state.pendingSpawnMaps, spawnMap],
    );
  }

  // ---- Private helpers ----

  List<SpawnRule> _rulesForLevel(int alertLevel, MissionDefinition mission) =>
      mission.spawnRules.where((r) => r.alertLevel == alertLevel).toList();

  SpawnPoint? _spawnPointById(String id, MissionDefinition mission) =>
      mission.spawnPoints.where((s) => s.id == id).firstOrNull;

  /// Finds the nearest free tile around (x, y) to place the enemy.
  /// Falls back to the spawn point itself if all adjacent tiles are occupied.
  (int, int) _resolveSpawnPosition(
    int x,
    int y,
    List<EnemyInstance> alreadyPlaced,
    GameState state,
  ) {
    final occupied = {
      for (final e in alreadyPlaced) (e.x, e.y),
      for (final p in state.players) (p.x, p.y),
    };

    if (!occupied.contains((x, y))) return (x, y);

    for (final (nx, ny) in _adjacents(x, y)) {
      if (!occupied.contains((nx, ny))) return (nx, ny);
    }

    return (x, y); // fallback: overlap (crowded spawn)
  }

  static List<(int, int)> _adjacents(int x, int y) => [
        (x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y),
        (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1),
      ];
}

/// Thin interface so SpawnSystem doesn't depend on EnemyCatalog directly.
/// Makes it easy to provide a fake in tests.
abstract class EnemyCatalogLookup {
  EnemyDefinition getById(String id);
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
