import '../core/models/zone.dart';
import 'asset_loader.dart';

// ---- Data models ----

class TileRect {
  final double x, y, w, h; // normalized 0..1 within tile image
  const TileRect({required this.x, required this.y, required this.w, required this.h});
}

class TileZone {
  final String id;
  final String name;
  final ZoneType type;
  final TileRect rect;   // position within tile (0..1)
  final List<String> tags;

  const TileZone({
    required this.id,
    required this.name,
    required this.type,
    required this.rect,
    this.tags = const [],
  });
}

class TileConnection {
  final String fromZone;
  final String toTile;
  final String toZone;
  final ConnectionType type;
  final String side; // north/south/east/west/internal
  bool isDoorOpen;

  TileConnection({
    required this.fromZone,
    required this.toTile,
    required this.toZone,
    required this.type,
    required this.side,
    this.isDoorOpen = false,
  });
}

class MapTile {
  final String id;
  final String name;
  final String image;          // asset name, e.g. "tile_lab"
  final int gridX, gridY;      // tile position in the overall map grid
  final List<TileZone> zones;
  final List<TileConnection> connections;
  final List<({String zone, double offsetX, double offsetY})> playerStart;
  final List<String> spawnZoneIds;

  const MapTile({
    required this.id,
    required this.name,
    required this.image,
    required this.gridX,
    required this.gridY,
    required this.zones,
    required this.connections,
    required this.playerStart,
    required this.spawnZoneIds,
  });

  TileZone? zoneById(String id) {
    try { return zones.firstWhere((z) => z.id == id); }
    catch (_) { return null; }
  }
}

class MapData {
  final List<MapTile> tiles;
  final int tilePixelSize;      // pixels per tile on screen
  final List<String> globalSpawnZoneIds;
  final String? background;     // single map image (e.g. "map_01"), null = use per-tile images
  final int gridCols;           // total grid width for background sizing (0 = auto from tiles)
  final int gridRows;           // total grid height for background sizing (0 = auto from tiles)

  const MapData({
    required this.tiles,
    required this.tilePixelSize,
    required this.globalSpawnZoneIds,
    this.background,
    this.gridCols = 0,
    this.gridRows = 0,
  });

  MapTile? tileById(String id) {
    try { return tiles.firstWhere((t) => t.id == id); }
    catch (_) { return null; }
  }

  /// World-space rect of a tile (in pixels).
  ({double x, double y, double w, double h}) tileWorldRect(MapTile tile) {
    final s = tilePixelSize.toDouble();
    return (x: tile.gridX * s, y: tile.gridY * s, w: s, h: s);
  }

  /// World-space rect of a zone (in pixels).
  ({double x, double y, double w, double h}) zoneWorldRect(MapTile tile, TileZone zone) {
    final r = tileWorldRect(tile);
    return (
      x: r.x + zone.rect.x * r.w,
      y: r.y + zone.rect.y * r.h,
      w: zone.rect.w * r.w,
      h: zone.rect.h * r.h,
    );
  }

  /// World-space center of a zone.
  ({double x, double y}) zoneCenter(MapTile tile, TileZone zone) {
    final r = tileWorldRect(tile);
    final cx = r.x + (zone.rect.x + zone.rect.w / 2) * r.w;
    final cy = r.y + (zone.rect.y + zone.rect.h / 2) * r.h;
    return (x: cx, y: cy);
  }

  /// All zones across all tiles.
  List<({MapTile tile, TileZone zone})> get allZones => [
    for (final t in tiles)
      for (final z in t.zones) (tile: t, zone: z),
  ];

  /// Find tile+zone by zone id.
  ({MapTile tile, TileZone zone})? findZone(String zoneId) {
    for (final t in tiles) {
      final z = t.zoneById(zoneId);
      if (z != null) return (tile: t, zone: z);
    }
    return null;
  }

  /// Adjacent zones reachable from [fromZoneId].
  /// [openDoorKeys] comes from GameState.openDoors — format "zoneA|zoneB".
  /// [ignoreDoors] treats all door connections as passable (used for enemy AI).
  /// Never mutates MapData — doors are tracked in GameState.
  List<({MapTile tile, TileZone zone})> adjacentZones(
    String fromZoneId, {
    List<String> openDoorKeys = const [],
    bool ignoreDoors = false,
  }) {
    final src = findZone(fromZoneId);
    if (src == null) return [];

    final result = <({MapTile tile, TileZone zone})>[];

    bool doorOpen(String a, String b) =>
        ignoreDoors ||
        openDoorKeys.contains('$a|$b') ||
        openDoorKeys.contains('$b|$a');

    for (final conn in src.tile.connections) {
      if (conn.fromZone != fromZoneId) continue;
      if (conn.type == ConnectionType.door &&
          !doorOpen(conn.fromZone, conn.toZone)) continue;

      if (conn.side == 'internal') {
        final z = src.tile.zoneById(conn.toZone);
        if (z != null) result.add((tile: src.tile, zone: z));
      } else {
        final destTile = tileById(conn.toTile);
        final destZone = destTile?.zoneById(conn.toZone);
        if (destTile != null && destZone != null) {
          result.add((tile: destTile, zone: destZone));
        }
      }
    }

    // Reverse connections.
    for (final t in tiles) {
      for (final conn in t.connections) {
        if (conn.toZone != fromZoneId) continue;
        if (conn.type == ConnectionType.door &&
            !doorOpen(conn.fromZone, conn.toZone)) continue;
        final srcZone = t.zoneById(conn.fromZone);
        if (srcZone != null && !result.any((r) => r.zone.id == srcZone.id)) {
          result.add((tile: t, zone: srcZone));
        }
      }
    }

    return result;
  }

  /// Key used to track open doors in GameState.openDoors.
  static String doorKey(String a, String b) => '$a|$b';

  /// Returns adjacent zone ids separated by a door (open or closed).
  List<String> closedDoorsAdjacentTo(String zoneId, List<String> openDoorKeys) {
    final result = <String>[];
    bool doorOpen(String a, String b) =>
        openDoorKeys.contains('$a|$b') || openDoorKeys.contains('$b|$a');

    for (final t in tiles) {
      for (final conn in t.connections) {
        if (conn.type != ConnectionType.door) continue;
        if (conn.fromZone != zoneId && conn.toZone != zoneId) continue;
        final other = conn.fromZone == zoneId ? conn.toZone : conn.fromZone;
        if (!doorOpen(conn.fromZone, conn.toZone)) {
          result.add(other);
        }
      }
    }
    return result;
  }

  /// Player start positions across all tiles.
  List<({String tileId, String zoneId, double offsetX, double offsetY})> get playerStartPositions {
    final result = <({String tileId, String zoneId, double offsetX, double offsetY})>[];
    for (final t in tiles) {
      for (final s in t.playerStart) {
        result.add((tileId: t.id, zoneId: s.zone, offsetX: s.offsetX, offsetY: s.offsetY));
      }
    }
    return result;
  }

  /// World-space pixel position for a player start slot.
  ({double x, double y}) playerStartWorldPos(int index) {
    final starts = playerStartPositions;
    if (starts.isEmpty) return (x: 100, y: 100);
    final s = starts[index % starts.length];
    final tile = tileById(s.tileId);
    if (tile == null) return (x: 100, y: 100);
    final r = tileWorldRect(tile);
    final zone = tile.zoneById(s.zoneId);
    if (zone == null) return (x: r.x + r.w * 0.5, y: r.y + r.h * 0.5);
    return (
      x: r.x + (zone.rect.x + zone.rect.w * s.offsetX) * r.w,
      y: r.y + (zone.rect.y + zone.rect.h * s.offsetY) * r.h,
    );
  }
}

// ---- Loader ----

class MapLoader {
  final AssetLoader _loader;
  const MapLoader(this._loader);

  Future<MapData> load(String missionId) async {
    final json = await _loader.loadJson('assets/data/maps/$missionId.json');
    return _parse(json);
  }

  MapData _parse(Map<String, dynamic> json) {
    final tilePixelSize = (json['tilePixelSize'] as int?) ?? 200;
    final rawTiles = (json['tiles'] as List? ?? []);

    final tiles = rawTiles.map((t) => _parseTile(t as Map<String, dynamic>)).toList();

    final spawnZones = (json['spawnZones'] as List? ?? []).cast<String>();
    final background = json['background'] as String?;
    final gridCols   = (json['gridCols'] as int?) ?? 0;
    final gridRows   = (json['gridRows'] as int?) ?? 0;

    return MapData(
      tiles: tiles,
      tilePixelSize: tilePixelSize,
      globalSpawnZoneIds: spawnZones,
      background: background,
      gridCols: gridCols,
      gridRows: gridRows,
    );
  }

  MapTile _parseTile(Map<String, dynamic> t) {
    final id    = t['id']    as String;
    final name  = t['name']  as String;
    final image = t['image'] as String;
    final gridX = t['gridX'] as int;
    final gridY = t['gridY'] as int;

    // Tags per zone
    final rawTags = (t['tags'] as Map<String, dynamic>?) ?? {};
    final zoneTags = rawTags.map((k, v) => MapEntry(k, (v as List).cast<String>()));

    // Zones
    final zones = (t['zones'] as List? ?? []).map((z) {
      final zid  = z['id']   as String;
      final rect = z['rect'] as Map<String, dynamic>;
      return TileZone(
        id: zid,
        name: z['name'] as String? ?? zid,
        type: _parseZoneType(z['type'] as String? ?? 'indoor'),
        rect: TileRect(
          x: (rect['x'] as num).toDouble(),
          y: (rect['y'] as num).toDouble(),
          w: (rect['w'] as num).toDouble(),
          h: (rect['h'] as num).toDouble(),
        ),
        tags: zoneTags[zid] ?? [],
      );
    }).toList();

    // Connections
    final connections = (t['connections'] as List? ?? []).map((c) => TileConnection(
      fromZone: c['fromZone'] as String,
      toTile:   c['toTile']   as String,
      toZone:   c['toZone']   as String,
      type:     _parseConnType(c['type'] as String? ?? 'open'),
      side:     c['side']     as String? ?? 'north',
    )).toList();

    // Player start
    final starts = (t['playerStart'] as List? ?? []).map((s) => (
      zone:    s['zone']    as String,
      offsetX: (s['offsetX'] as num).toDouble(),
      offsetY: (s['offsetY'] as num).toDouble(),
    )).toList();

    // Spawn zones
    final spawnZones = (t['spawnPoints'] as List? ?? []).cast<String>();

    return MapTile(
      id: id, name: name, image: image,
      gridX: gridX, gridY: gridY,
      zones: zones, connections: connections,
      playerStart: starts, spawnZoneIds: spawnZones,
    );
  }

  static ZoneType _parseZoneType(String s) => switch (s) {
    'street'     => ZoneType.street,
    'extraction' => ZoneType.extraction,
    'outdoor'    => ZoneType.outdoor,
    _            => ZoneType.indoor,
  };

  static ConnectionType _parseConnType(String s) => switch (s) {
    'door' => ConnectionType.door,
    'wall' => ConnectionType.wall,
    _      => ConnectionType.open,
  };
}
