import '../models/player.dart';

class MovementRules {
  /// Zone IDs reachable by [player] in one move action (BFS up to movementRange hops).
  /// Returns empty set if no actions remaining or no map data.
  static Set<String> reachableZones(PlayerState player, dynamic mapData) {
    if (player.actionsRemaining <= 0 || mapData == null) return {};

    final maxHops = player.movementRange;
    final visited = <String, int>{player.zoneId: 0};
    final queue   = [player.zoneId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final dist    = visited[current]!;
      if (dist >= maxHops) continue;

      for (final adj in _adjacentZoneIds(current, mapData)) {
        if (!visited.containsKey(adj)) {
          visited[adj] = dist + 1;
          queue.add(adj);
        }
      }
    }

    visited.remove(player.zoneId);
    return visited.keys.toSet();
  }

  /// Whether [player] can attack [targetZoneId] given [range].
  /// range=1 → same zone or adjacent; range>1 → BFS.
  static bool canAttack(
    PlayerState player,
    String targetZoneId,
    dynamic mapData, {
    int range = 1,
  }) {
    if (player.actionsRemaining <= 0) return false;
    if (player.zoneId == targetZoneId) return true;
    if (range <= 0) return false;

    // BFS up to range hops.
    final visited = <String>{player.zoneId};
    var frontier  = [player.zoneId];
    for (var depth = 0; depth < range; depth++) {
      final next = <String>[];
      for (final z in frontier) {
        for (final adj in _adjacentZoneIds(z, mapData)) {
          if (adj == targetZoneId) return true;
          if (visited.add(adj)) next.add(adj);
        }
      }
      frontier = next;
    }
    return false;
  }

  /// Zone IDs attackable from player's current position for [range] hops.
  static Set<String> attackableZones(
    PlayerState player,
    dynamic mapData, {
    int range = 1,
  }) {
    if (player.actionsRemaining <= 0) return {};

    final visited = <String, int>{player.zoneId: 0};
    final queue   = [player.zoneId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final dist    = visited[current]!;
      if (dist >= range) continue;

      for (final adj in _adjacentZoneIds(current, mapData)) {
        if (!visited.containsKey(adj)) {
          visited[adj] = dist + 1;
          queue.add(adj);
        }
      }
    }

    visited.remove(player.zoneId);
    return visited.keys.toSet();
  }

  static List<String> _adjacentZoneIds(String zoneId, dynamic mapData) {
    try {
      return (mapData.adjacentZones(zoneId) as Iterable)
          .map<String>((e) => e.zone.id as String)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
