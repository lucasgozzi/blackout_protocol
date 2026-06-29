import 'dart:collection';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/tile.dart';

class MovementRules {
  /// Zombicide movement model:
  /// 1 action = move up to [player.movementRange] tiles.
  /// Returns all reachable tiles across ALL remaining actions.
  static Map<(int, int), int> reachableTiles(
    PlayerState player,
    GameMap map,
    GameState state,
  ) {
    if (player.actionsRemaining <= 0) return {};

    // Total tiles reachable = movementRange * actionsRemaining
    final maxTiles = player.movementRange * player.actionsRemaining;

    final visited = <(int, int), int>{}; // position → tiles spent
    final queue = Queue<({int x, int y, int tilesSpent})>();

    queue.add((x: player.x, y: player.y, tilesSpent: 0));
    visited[(player.x, player.y)] = 0;

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current.tilesSpent >= maxTiles) continue;

      for (final (nx, ny) in _neighbors(current.x, current.y)) {
        if (!map.isWalkable(nx, ny)) continue;
        if (_isOccupiedByEnemy(nx, ny, state)) continue;

        final cost = current.tilesSpent + 1;
        if (!visited.containsKey((nx, ny)) || visited[(nx, ny)]! > cost) {
          visited[(nx, ny)] = cost;
          queue.add((x: nx, y: ny, tilesSpent: cost));
        }
      }
    }

    visited.remove((player.x, player.y));
    return visited;
  }

  /// Actions consumed to reach (tx, ty) from the player's current position.
  /// Returns 0 if already there, or the number of move actions needed.
  static int actionsToMove(PlayerState player, int tx, int ty) {
    final tiles = (tx - player.x).abs() + (ty - player.y).abs();
    return (tiles / player.movementRange).ceil();
  }

  /// Whether [player] can attack a target at (tx, ty).
  static bool canAttack(
    PlayerState player,
    int tx,
    int ty,
    GameMap map, {
    int range = 1,
  }) {
    if (player.actionsRemaining <= 0) return false;
    final dist = _chebyshev(player.x, player.y, tx, ty);
    if (dist > range) return false;
    if (range > 1) return _hasLineOfSight(player.x, player.y, tx, ty, map);
    return true;
  }

  /// Tiles the player can attack from current position.
  static List<(int, int)> attackableTiles(
    PlayerState player,
    GameMap map, {
    int range = 1,
  }) {
    final result = <(int, int)>[];
    for (var dy = -range; dy <= range; dy++) {
      for (var dx = -range; dx <= range; dx++) {
        if (dx == 0 && dy == 0) continue;
        final tx = player.x + dx;
        final ty = player.y + dy;
        if (!map.inBounds(tx, ty)) continue;
        if (_chebyshev(player.x, player.y, tx, ty) > range) continue;
        if (range > 1 && !_hasLineOfSight(player.x, player.y, tx, ty, map)) continue;
        result.add((tx, ty));
      }
    }
    return result;
  }

  static List<(int, int)> _neighbors(int x, int y) => [
        (x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y),
      ];

  static bool _isOccupiedByEnemy(int x, int y, GameState state) =>
      state.enemies.any((e) => e.x == x && e.y == y);

  static int _chebyshev(int x1, int y1, int x2, int y2) =>
      (x2 - x1).abs() > (y2 - y1).abs() ? (x2 - x1).abs() : (y2 - y1).abs();

  static bool _hasLineOfSight(int x0, int y0, int x1, int y1, GameMap map) {
    int dx = (x1 - x0).abs();
    int dy = -(y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1;
    int sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    int cx = x0, cy = y0;

    while (true) {
      if (cx == x1 && cy == y1) return true;
      if (!(cx == x0 && cy == y0) && !(cx == x1 && cy == y1)) {
        if (!map.hasLineOfSight(cx, cy)) return false;
      }
      final e2 = 2 * err;
      if (e2 >= dy) { err += dy; cx += sx; }
      if (e2 <= dx) { err += dx; cy += sy; }
    }
  }
}
