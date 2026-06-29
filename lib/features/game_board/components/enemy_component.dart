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

  ui.Image? _tokenImage;
  static final Map<String, ui.Image?> _imageCache = {};

  EnemyComponent({
    required this.enemy,
    required this.onTap,
  }) : super(size: Vector2.all(BoardConstants.pieceSize), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    position = _worldPos(enemy.x, enemy.y);
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

  static Vector2 _worldPos(int gx, int gy) =>
      Vector2(gx.toDouble(), gy.toDouble());

  void updateState(EnemyInstance newEnemy) {
    enemy = newEnemy;
    position = _worldPos(newEnemy.x, newEnemy.y);
    // Load image if definition changed
    if (_tokenImage == null) {
      _loadImage(newEnemy.definitionId).then((img) => _tokenImage = img);
    }
  }

  bool get _isBoss => enemy.definitionId.contains('abomination');
  Color get _color  => _isBoss ? BoardConstants.enemyBoss : BoardConstants.enemyColor;

  @override
  void render(Canvas canvas) {
    final s = BoardConstants.pieceSize;
    final r = s / 2;
    final center = Offset(r, r);

    // Boss glow
    if (_isBoss) {
      canvas.drawCircle(center, r + 6, Paint()
        ..color = _color.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    if (_tokenImage != null) {
      // Draw token image fitted inside the component, preserving aspect ratio
      final imgW = _tokenImage!.width.toDouble();
      final imgH = _tokenImage!.height.toDouble();
      final scale = (imgW > imgH) ? s / imgW : s / imgH;
      final drawW = imgW * scale;
      final drawH = imgH * scale;
      final dx = (s - drawW) / 2;
      final dy = (s - drawH) / 2;

      final src = Rect.fromLTWH(0, 0, imgW, imgH);
      final dst = Rect.fromLTWH(dx, dy, drawW, drawH);
      canvas.drawImageRect(_tokenImage!, src, dst, Paint());

      // HP bar below token
      _renderHpBar(canvas, s);
    } else {
      _renderPlaceholder(canvas, center, r, s);
    }
  }

  void _renderPlaceholder(Canvas canvas, Offset center, double r, double s) {
    // Diamond shape
    final path = Path()
      ..moveTo(center.dx, center.dy - r + 3)
      ..lineTo(center.dx + r - 3, center.dy)
      ..lineTo(center.dx, center.dy + r - 3)
      ..lineTo(center.dx - r + 3, center.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = _color.withOpacity(0.15));
    canvas.drawPath(path, Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _isBoss ? 2.5 : 1.5);

    // Letter
    final letter = switch (enemy.definitionId) {
      String d when d.contains('drone')    => 'D',
      String d when d.contains('infected') => 'I',
      String d when d.contains('security') => 'S',
      _ => '?',
    };
    final tp = TextPainter(
      text: TextSpan(text: letter, style: TextStyle(
        color: _color, fontSize: _isBoss ? 18 : 14, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2 + 2));

    _renderHpBar(canvas, s);
  }

  void _renderHpBar(Canvas canvas, double s) {
    final maxHp = _isBoss ? 10 : 3;
    final frac  = (enemy.currentHp / maxHp).clamp(0.0, 1.0);
    final barW  = s - 8;
    final barY  = s - 6.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, barY, barW, 4), const Radius.circular(2)),
      Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, barY, barW * frac, 4), const Radius.circular(2)),
      Paint()..color = _color);
  }

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
