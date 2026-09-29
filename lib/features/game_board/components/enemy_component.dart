import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/enemy.dart';
import '../board_constants.dart';

class EnemyComponent extends PositionComponent with TapCallbacks {
  EnemyInstance enemy;
  final VoidCallback onTap;

  // When false this instance is a duplicate in the same tile — render nothing.
  bool isVisible = true;
  // Total enemies of this type at this tile (shown as badge inside token).
  int count = 1;

  ui.Image? _tokenImage;
  static final Map<String, ui.Image?> _imageCache = {};

  EnemyComponent({
    required this.enemy,
    required this.onTap,
  }) : super(size: Vector2.all(BoardConstants.pieceSize), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    // Position is managed externally by GameBoardGame._syncEnemies
    _tokenImage = await _loadImage(enemy.definitionId);
  }

  static Future<ui.Image?> _loadImage(String definitionId) async {
    if (_imageCache.containsKey(definitionId)) return _imageCache[definitionId];
    try {
      final path = 'assets/sprites/enemies/${definitionId}_token.png';
      final data  = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _imageCache[definitionId] = frame.image;
      return frame.image;
    } catch (_) {
      _imageCache[definitionId] = null;
      return null;
    }
  }

  void updateState(EnemyInstance newEnemy) {
    enemy = newEnemy;
    if (_tokenImage == null) {
      _loadImage(newEnemy.definitionId).then((img) => _tokenImage = img);
    }
  }

  bool get _isBoss => enemy.definitionId.contains('abomination');
  Color get _color  => _isBoss ? BoardConstants.enemyBoss : BoardConstants.enemyColor;

  Path _diamondPath(Offset center, double r) => Path()
    ..moveTo(center.dx, center.dy - r + 2)
    ..lineTo(center.dx + r - 2, center.dy)
    ..lineTo(center.dx, center.dy + r - 2)
    ..lineTo(center.dx - r + 2, center.dy)
    ..close();

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    final s = BoardConstants.pieceSize;
    final r = s / 2;
    final center = Offset(r, r);
    final diamond = _diamondPath(center, r);

    if (_isBoss) {
      canvas.drawCircle(center, r + 6, Paint()
        ..color = _color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    if (_tokenImage != null) {
      canvas.save();
      canvas.clipPath(diamond);

      final imgW  = _tokenImage!.width.toDouble();
      final imgH  = _tokenImage!.height.toDouble();
      final scale = (imgW < imgH) ? s / imgW : s / imgH;
      final drawW = imgW * scale;
      final drawH = imgH * scale;
      canvas.drawImageRect(
        _tokenImage!,
        Rect.fromLTWH(0, 0, imgW, imgH),
        Rect.fromLTWH((s - drawW) / 2, (s - drawH) / 2, drawW, drawH),
        Paint(),
      );
      canvas.restore();

      canvas.drawPath(diamond, Paint()
        ..color = _color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _isBoss ? 2.5 : 1.5);
    } else {
      _renderPlaceholder(canvas, center, r);
    }

    if (count > 1) _renderCountBadge(canvas, center, r);
  }

  void _renderPlaceholder(Canvas canvas, Offset center, double r) {
    final path = _diamondPath(center, r);
    canvas.drawPath(path, Paint()..color = _color.withValues(alpha: 0.15));
    canvas.drawPath(path, Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _isBoss ? 2.5 : 1.5);

    final letter = switch (enemy.definitionId) {
      String d when d.contains('runner')      => 'R',
      String d when d.contains('fatty')       => 'F',
      String d when d.contains('abomination') => 'A',
      _                                       => 'W',
    };
    final tp = TextPainter(
      text: TextSpan(text: letter, style: TextStyle(
        color: _color, fontSize: _isBoss ? 18 : 14, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _renderCountBadge(Canvas canvas, Offset center, double r) {
    // Small badge in the bottom-right corner of the diamond.
    final bx = center.dx + r * 0.45;
    final by = center.dy + r * 0.45;
    const br = 7.0;

    canvas.drawCircle(Offset(bx, by), br, Paint()..color = const Color(0xFF111118));
    canvas.drawCircle(Offset(bx, by), br, Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    final tp = TextPainter(
      text: TextSpan(text: '$count', style: TextStyle(
        color: _color, fontSize: 9, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(bx - tp.width / 2, by - tp.height / 2));
  }

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
