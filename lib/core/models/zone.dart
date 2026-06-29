enum ZoneType { indoor, street, extraction, outdoor }

enum ConnectionType { open, door, wall }

class ZoneConnection {
  final String fromId;
  final String toId;
  final ConnectionType type;
  bool isDoorOpen;

  ZoneConnection({
    required this.fromId,
    required this.toId,
    required this.type,
    this.isDoorOpen = false,
  });
}

class Zone {
  final String id;
  final String name;
  final ZoneType type;
  final List<(int, int)> tiles; // grid tiles this zone occupies
  final List<String> tags;

  const Zone({
    required this.id,
    required this.name,
    required this.type,
    required this.tiles,
    this.tags = const [],
  });

  bool containsTile(int x, int y) => tiles.any((t) => t.$1 == x && t.$2 == y);

  // Center tile for placing pieces / camera
  (int, int) get center {
    final avgX = tiles.map((t) => t.$1).reduce((a, b) => a + b) ~/ tiles.length;
    final avgY = tiles.map((t) => t.$2).reduce((a, b) => a + b) ~/ tiles.length;
    return (avgX, avgY);
  }
}

class ZoneMap {
  final List<Zone> zones;
  final List<ZoneConnection> connections;

  const ZoneMap({required this.zones, required this.connections});

  Zone? zoneById(String id) {
    try { return zones.firstWhere((z) => z.id == id); }
    catch (_) { return null; }
  }

  Zone? zoneAt(int x, int y) {
    try { return zones.firstWhere((z) => z.containsTile(x, y)); }
    catch (_) { return null; }
  }

  /// Adjacent zones reachable from [zoneId] (not blocked by closed door).
  List<Zone> adjacentZones(String zoneId) {
    final reachable = <Zone>[];
    for (final conn in connections) {
      String? otherId;
      if (conn.fromId == zoneId) otherId = conn.toId;
      if (conn.toId   == zoneId) otherId = conn.fromId;
      if (otherId == null) continue;

      // Door blocks unless open.
      if (conn.type == ConnectionType.door && !conn.isDoorOpen) continue;
      if (conn.type == ConnectionType.wall) continue;

      final other = zoneById(otherId);
      if (other != null) reachable.add(other);
    }
    return reachable;
  }

  ZoneConnection? connectionBetween(String a, String b) {
    try {
      return connections.firstWhere(
        (c) => (c.fromId == a && c.toId == b) || (c.fromId == b && c.toId == a),
      );
    } catch (_) {
      return null;
    }
  }

  bool hasLOS(String fromZoneId, String toZoneId) {
    // Indoor: can only see adjacent zones through openings.
    // Street: can see multiple zones in a straight line.
    // Simple rule: can see any directly connected zone (open or door-open).
    final fromZone = zoneById(fromZoneId);
    final toZone   = zoneById(toZoneId);
    if (fromZone == null || toZone == null) return false;
    if (fromZoneId == toZoneId) return true;

    final conn = connectionBetween(fromZoneId, toZoneId);
    if (conn == null) return false;
    if (conn.type == ConnectionType.wall) return false;
    if (conn.type == ConnectionType.door) return conn.isDoorOpen;

    // Street zones: extend LOS further along axis.
    if (fromZone.type == ZoneType.street && toZone.type == ZoneType.street) {
      return true;
    }
    return true;
  }

  void openDoor(String fromId, String toId) {
    for (final conn in connections) {
      if ((conn.fromId == fromId && conn.toId == toId) ||
          (conn.fromId == toId  && conn.toId == fromId)) {
        conn.isDoorOpen = true;
      }
    }
  }
}
