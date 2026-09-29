import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/enemy.dart';
import '../models/mission.dart';

const _uuid = Uuid();

class SpawnSystem {
  final EnemyCatalogLookup catalog;

  const SpawnSystem({required this.catalog});

  /// Spawns enemies according to rules triggered at the current alert level.
  GameState spawnForAlertLevel(GameState state, MissionDefinition mission) {
    final rules = mission.spawnRules.where((r) => r.alertLevel == state.alertLevel).toList();
    if (rules.isEmpty) return state;

    final newEnemies = <EnemyInstance>[];
    final logEntries = <String>[];

    for (final rule in rules) {
      final spawnPoint = mission.spawnPoints
          .where((s) => s.id == rule.spawnPointId)
          .firstOrNull;
      if (spawnPoint == null) continue;

      final def = catalog.getById(rule.enemyId);
      for (var i = 0; i < rule.count; i++) {
        newEnemies.add(EnemyInstance(
          instanceId:   _uuid.v4(),
          definitionId: rule.enemyId,
          currentHp:    def.hp,
          zoneId:       spawnPoint.id,
        ));
      }
      logEntries.add('Spawned ${rule.count}x ${rule.enemyId} at ${rule.spawnPointId}');
    }

    return state.copyWith(
      enemies:  [...state.enemies, ...newEnemies],
      eventLog: [...state.eventLog, ...logEntries].takeLast(20).toList(),
    );
  }

  /// Spawns enemies from a specific AlertEvent (boss spawns, wave events, etc.).
  GameState spawnFromEvent(GameState state, MissionDefinition mission, AlertEvent event) {
    if (event.eventType != 'spawn_wave' && event.eventType != 'spawn_boss') {
      return state;
    }

    final enemyId      = event.params['enemyId'] as String;
    final count        = event.params['count'] as int;
    final spawnPointId = event.params['spawnPointId'] as String;
    final spawnPoint   = mission.spawnPoints
        .where((s) => s.id == spawnPointId)
        .firstOrNull;
    if (spawnPoint == null) return state;

    final def        = catalog.getById(enemyId);
    final newEnemies = List.generate(count, (_) => EnemyInstance(
      instanceId:   _uuid.v4(),
      definitionId: enemyId,
      currentHp:    def.hp,
      zoneId:       spawnPointId,
    ));

    final log = '${event.description} — spawned ${count}x $enemyId';
    return state.copyWith(
      enemies:  [...state.enemies, ...newEnemies],
      eventLog: [...state.eventLog, log].takeLast(20).toList(),
    );
  }

  /// Spawn enemies directly into a zone by zone ID.
  GameState spawnInZone(
    GameState state,
    String zoneId,
    String enemyId,
    int count, {
    String zoneName = '',
  }) {
    final def        = catalog.getById(enemyId);
    final newEnemies = List.generate(count, (_) => EnemyInstance(
      instanceId:   _uuid.v4(),
      definitionId: enemyId,
      currentHp:    def.hp,
      zoneId:       zoneId,
    ));

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
      enemies:          [...state.enemies, ...newEnemies],
      eventLog:         [...state.eventLog, log].takeLast(20).toList(),
      pendingSpawnMaps: [...state.pendingSpawnMaps, spawnMap],
    );
  }
}

/// Thin interface so SpawnSystem doesn't depend on EnemyCatalog directly.
abstract class EnemyCatalogLookup {
  EnemyDefinition getById(String id);
}

extension _ListTakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
