import '../models/game_state.dart';

class NoiseSystem {
  static const int survivorNoise = 1;

  static GameState addNoise(GameState state, String zoneId, int amount) {
    final updated = Map<String, int>.from(state.noiseTokens);
    updated[zoneId] = (updated[zoneId] ?? 0) + amount;
    return state.copyWith(noiseTokens: updated);
  }

  static GameState clearNoise(GameState state) =>
      state.copyWith(noiseTokens: {});

  static int noiseAt(GameState state, String zoneId) {
    final tokens = state.noiseTokens[zoneId] ?? 0;
    final survivors = state.players
        .where((p) => !p.isEliminated && p.zoneId == zoneId)
        .length;
    return tokens + survivors * survivorNoise;
  }

  static List<({String zoneId, int noise})> allNoisyZones(GameState state) {
    final seen = <String>{};
    final zones = <({String zoneId, int noise})>[];

    for (final p in state.players.where((p) => !p.isEliminated)) {
      if (seen.add(p.zoneId)) {
        final n = noiseAt(state, p.zoneId);
        if (n > 0) zones.add((zoneId: p.zoneId, noise: n));
      }
    }

    for (final entry in state.noiseTokens.entries) {
      if (seen.add(entry.key)) {
        final n = noiseAt(state, entry.key);
        if (n > 0) zones.add((zoneId: entry.key, noise: n));
      }
    }

    zones.sort((a, b) => b.noise.compareTo(a.noise));
    return zones;
  }

  static String? noisiestZone(GameState state) {
    final noisy = allNoisyZones(state);
    return noisy.isEmpty ? null : noisy.first.zoneId;
  }
}
