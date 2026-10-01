import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../board_constants.dart';

class ItemComponent extends PositionComponent {
  final String tag;
  final double _displaySize;
  bool _collected = false;

  ItemComponent({
    required int gridX,
    required int gridY,
    required this.tag,
  })  : _displaySize = BoardConstants.tileSize,
        super(
          position: Vector2(
            BoardConstants.boardPadding + gridX * BoardConstants.tileSize,
            BoardConstants.boardPadding + gridY * BoardConstants.tileSize,
          ),
          size: Vector2.all(BoardConstants.tileSize),
          anchor: Anchor.center,
        );

  /// World-position constructor for tile-based maps.
  ItemComponent.world({
    required double worldX,
    required double worldY,
    required this.tag,
    double size = 30,
  })  : _displaySize = size,
        super(
          position: Vector2(worldX, worldY),
          size: Vector2.all(size),
          anchor: Anchor.center,
        );

  bool _hidden = false;
  void setCollected(bool collected) => _collected = collected;
  void setHidden(bool hidden) => _hidden = hidden;

  static bool hasKnownIcon(String tag) =>
      tag.contains('fuel') ||
      tag.contains('extraction') ||
      tag.contains('scientist') ||
      tag.contains('server') ||
      tag.contains('antenna') ||
      tag.contains('datapad');

  String get _icon {
    if (tag.contains('fuel'))       return '⛽';
    if (tag.contains('extraction')) return '↑';
    if (tag.contains('scientist'))  return '👤';
    if (tag.contains('server'))     return '💾';
    if (tag.contains('antenna'))    return '📡';
    if (tag.contains('datapad'))    return '📋';
    return '◉';
  }

  Color get _color {
    if (tag.contains('fuel'))      return const Color(0xFFFFAA00);
    if (tag.contains('scientist')) return const Color(0xFF00AAFF);
    if (tag.contains('antenna'))   return const Color(0xFFFF4444);
    return const Color(0xFF00FF88);
  }

  @override
  void render(Canvas canvas) {
    if (_hidden) return;
    final cx = _displaySize / 2;
    final cy = _displaySize / 2;

    if (_collected) {
      final tp = TextPainter(
        text: TextSpan(text: '📦', style: TextStyle(fontSize: _displaySize)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      return;
    }

    // Glow ring.
    canvas.drawCircle(
      Offset(cx, cy), _displaySize * 0.4,
      Paint()
        ..color = _color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Icon.
    final tp = TextPainter(
      text: TextSpan(text: _icon, style: TextStyle(fontSize: _displaySize)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }
}
