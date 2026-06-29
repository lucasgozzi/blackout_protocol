import '../models/game_state.dart';
import '../models/player.dart';
import '../models/tile.dart';

class NoiseSystem {
  static const int survivorNoise = 1; // each survivor adds 1 noise to their zone

  /// Add noise tokens to a zone (noisy weapon action).
  static GameState addNoise(GameState state, int x, int y, int amount) {
    final key = '$x,$y';
    final updated = Map<String, int>.from(state.noiseTokens);
    updated[key] = (updated[key] ?? 0) + amount;
    return state.copyWith(noiseTokens: updated);
  }

  /// Clear all noise tokens — called after zombie phase.
  static GameState clearNoise(GameState state) =>
      state.copyWith(noiseTokens: {});

  /// Total noise at a zone = tokens + number of survivors there.
  static int noiseAt(GameState state, int x, int y) {
    final tokens = state.noiseTokens['$x,$y'] ?? 0;
    final survivors = state.players
        .where((p) => !p.isEliminated && p.x == x && p.y == y)
        .length;
    return tokens + survivors * survivorNoise;
  }

  /// All zones with non-zero noise, sorted by noise descending.
  static List<({int x, int y, int noise})> allNoisyZones(GameState state) {
    final zones = <({int x, int y, int noise})>[];

    // Survivor zones.
    for (final p in state.players.where((p) => !p.isEliminated)) {
      final n = noiseAt(state, p.x, p.y);
      if (n > 0 && !zones.any((z) => z.x == p.x && z.y == p.y)) {
        zones.add((x: p.x, y: p.y, noise: n));
      }
    }

    // Token-only zones.
    for (final entry in state.noiseTokens.entries) {
      final parts = entry.key.split(',');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);
      if (!zones.any((z) => z.x == x && z.y == y)) {
        final n = noiseAt(state, x, y);
        if (n > 0) zones.add((x: x, y: y, noise: n));
      }
    }

    zones.sort((a, b) => b.noise.compareTo(a.noise));
    return zones;
  }

  /// Noisiest zone visible from (fromX, fromY) using LOS.
  /// Returns null if no noisy zones visible.
  static ({int x, int y})? noisiestVisibleZone(
    GameState state,
    int fromX,
    int fromY,
    GameMap map,
  ) {
    final noisy = allNoisyZones(state);
    for (final zone in noisy) {
      if (_hasLOS(fromX, fromY, zone.x, zone.y, map)) {
        return (x: zone.x, y: zone.y);
      }
    }
    return null;
  }

  /// Noisiest zone overall (for zombies with no LOS to any survivor).
  static ({int x, int y})? noisiestZone(GameState state) {
    final noisy = allNoisyZones(state);
    return noisy.isEmpty ? null : (x: noisy.first.x, y: noisy.first.y);
  }

  // Bresenham LOS check.
  static bool _hasLOS(int x0, int y0, int x1, int y1, GameMap map) {
    int dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    int err = dx + dy, cx = x0, cy = y0;
    while (true) {
      if (cx == x1 && cy == y1) return true;
      if (!(cx == x0 && cy == y0) && !map.hasLineOfSight(cx, cy)) return false;
      final e2 = 2 * err;
      if (e2 >= dy) { err += dy; cx += sx; }
      if (e2 <= dx) { err += dx; cy += sy; }
    }
  }
}
