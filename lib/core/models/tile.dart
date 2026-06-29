enum TileType { floor, wall, door, extraction, objective }

class Tile {
  final int x;
  final int y;
  final TileType type;
  final bool blocksMovement;
  final bool blocksLOS;
  final List<String> tags;
  final bool isDoorOpen;

  const Tile({
    required this.x,
    required this.y,
    required this.type,
    this.blocksMovement = false,
    this.blocksLOS = false,
    this.tags = const [],
    this.isDoorOpen = false,
  });

  Tile copyWith({
    int? x,
    int? y,
    TileType? type,
    bool? blocksMovement,
    bool? blocksLOS,
    List<String>? tags,
    bool? isDoorOpen,
  }) =>
      Tile(
        x: x ?? this.x,
        y: y ?? this.y,
        type: type ?? this.type,
        blocksMovement: blocksMovement ?? this.blocksMovement,
        blocksLOS: blocksLOS ?? this.blocksLOS,
        tags: tags ?? this.tags,
        isDoorOpen: isDoorOpen ?? this.isDoorOpen,
      );
}

class GameMap {
  final int width;
  final int height;
  final List<List<Tile>> _grid; // [y][x]

  GameMap({required this.width, required this.height, required List<List<Tile>> grid})
      : _grid = grid;

  Tile tileAt(int x, int y) => _grid[y][x];

  bool inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  bool isWalkable(int x, int y) {
    if (!inBounds(x, y)) return false;
    final t = tileAt(x, y);
    if (t.blocksMovement) return false;
    if (t.type == TileType.door) return t.isDoorOpen;
    return true;
  }

  bool hasLineOfSight(int x, int y) {
    if (!inBounds(x, y)) return false;
    return !tileAt(x, y).blocksLOS;
  }

  List<Tile> tilesWithTag(String tag) => _grid
      .expand((row) => row)
      .where((t) => t.tags.contains(tag))
      .toList();

  static GameMap flat(int width, int height) {
    final grid = List.generate(
      height,
      (y) => List.generate(
        width,
        (x) => Tile(x: x, y: y, type: TileType.floor),
      ),
    );
    return GameMap(width: width, height: height, grid: grid);
  }
}
