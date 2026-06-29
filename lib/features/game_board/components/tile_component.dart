import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../../../core/models/tile.dart';
import '../../../core/models/zone.dart';
import '../board_constants.dart';

enum TileHighlight { none, reachable, attack, objective, door }

class TileComponent extends PositionComponent with TapCallbacks {
  final int gridX;
  final int gridY;
  final VoidCallback onTap;
  TileType tileType;
  ZoneType? zoneType;
  final List<String> tags;
  bool isZoneBorderRight  = false;
  bool isZoneBorderBottom = false;
  bool isZoneBorderLeft   = false;
  bool isZoneBorderTop    = false;

  TileHighlight _highlight = TileHighlight.none;

  TileComponent({
    required this.gridX,
    required this.gridY,
    required this.onTap,
    this.tileType = TileType.floor,
    this.zoneType,
    this.tags = const [],
  }) : super(
          position: Vector2(
            BoardConstants.boardPadding + gridX * BoardConstants.tileSize,
            BoardConstants.boardPadding + gridY * BoardConstants.tileSize,
          ),
          size: Vector2.all(BoardConstants.tileSize),
        );

  void setHighlight(TileHighlight h) => _highlight = h;

  void setZoneBorders({bool right = false, bool bottom = false, bool left = false, bool top = false}) {
    isZoneBorderRight  = right;
    isZoneBorderBottom = bottom;
    isZoneBorderLeft   = left;
    isZoneBorderTop    = top;
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();

    // ---- Base fill ----
    final baseColor = tileType == TileType.wall
        ? BoardConstants.tileWall
        : tileType == TileType.extraction
            ? BoardConstants.zoneExtraction
            : zoneType == ZoneType.street
                ? BoardConstants.zoneStreet
                : BoardConstants.zoneIndoor;

    canvas.drawRect(rect, Paint()..color = baseColor);

    // ---- Highlight overlay ----
    if (_highlight != TileHighlight.none && tileType != TileType.wall) {
      final overlayColor = switch (_highlight) {
        TileHighlight.reachable => BoardConstants.highlightReachable,
        TileHighlight.attack    => BoardConstants.highlightAttack,
        TileHighlight.objective => BoardConstants.highlightObjective,
        TileHighlight.door      => BoardConstants.highlightDoor,
        TileHighlight.none      => Colors.transparent,
      };
      canvas.drawRect(rect, Paint()..color = overlayColor);
    }

    // ---- Wall hatching ----
    if (tileType == TileType.wall) {
      final hatch = Paint()..color = const Color(0xFF0F0F18)..strokeWidth = 0.5;
      for (var i = 0; i < BoardConstants.tileSize.toInt() * 2; i += 6) {
        final s = i.toDouble();
        canvas.drawLine(Offset(s - BoardConstants.tileSize, 0), Offset(s, BoardConstants.tileSize), hatch);
      }
      return; // no border on walls
    }

    // ---- Door indicator ----
    if (tileType == TileType.door) {
      final doorRect = Rect.fromLTWH(6, BoardConstants.tileSize / 2 - 2, BoardConstants.tileSize - 12, 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(doorRect, const Radius.circular(2)),
        Paint()..color = const Color(0xFF5544AA).withOpacity(0.7),
      );
    }

    // ---- Extraction arrow ----
    if (tileType == TileType.extraction || tags.contains('extraction_zone')) {
      final tp = TextPainter(
        text: const TextSpan(text: '▲', style: TextStyle(color: Color(0x6600FF88), fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(BoardConstants.tileSize / 2 - tp.width / 2,
                              BoardConstants.tileSize / 2 - tp.height / 2));
    }

    // ---- Grid border (subtle inner lines) ----
    canvas.drawRect(rect, Paint()
      ..color = const Color(0xFF1A1A28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3);

    // ---- Zone borders (thick bright lines at zone edges) ----
    final zoneBorderPaint = Paint()
      ..color = zoneType == ZoneType.street
          ? const Color(0xFF3A3A55)
          : const Color(0xFF2A2A40)
      ..strokeWidth = 1.5;

    if (isZoneBorderTop)    canvas.drawLine(Offset.zero, Offset(BoardConstants.tileSize, 0), zoneBorderPaint);
    if (isZoneBorderLeft)   canvas.drawLine(Offset.zero, Offset(0, BoardConstants.tileSize), zoneBorderPaint);
    if (isZoneBorderRight)  canvas.drawLine(Offset(BoardConstants.tileSize, 0), Offset(BoardConstants.tileSize, BoardConstants.tileSize), zoneBorderPaint);
    if (isZoneBorderBottom) canvas.drawLine(Offset(0, BoardConstants.tileSize), Offset(BoardConstants.tileSize, BoardConstants.tileSize), zoneBorderPaint);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (tileType != TileType.wall) onTap();
  }
}
