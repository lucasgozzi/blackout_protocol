import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/player.dart';
import '../board_constants.dart';

class PlayerComponent extends PositionComponent with TapCallbacks {
  PlayerState player;
  bool _isActive;
  final VoidCallback onTap;

  ui.Image? _tokenImage;

  static const _tokenSize = 40.0;

  PlayerComponent({
    required this.player,
    required bool isActive,
    required this.onTap,
  })  : _isActive = isActive,
        super(size: Vector2.all(_tokenSize), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try {
      final path = 'assets/sprites/characters/${player.definitionId}_token.png';
      final data  = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _tokenImage = frame.image;
    } catch (_) {
      // No image yet — renders placeholder
    }
  }

  void updateState(PlayerState newState) => player = newState;
  void setActive(bool active) => _isActive = active;

  Color get _dangerColor => switch (player.dangerLevel) {
    DangerLevel.blue   => BoardConstants.playerBlue,
    DangerLevel.yellow => BoardConstants.playerYellow,
    DangerLevel.orange => BoardConstants.playerOrange,
    DangerLevel.red    => BoardConstants.playerRed,
  };

  @override
  void render(Canvas canvas) {
    const r = _tokenSize / 2;
    final center = Offset(r, r);

    if (_isActive) {
      canvas.drawCircle(center, r + 5,
          Paint()
            ..color = _dangerColor.withOpacity(0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    if (_tokenImage != null) {
      // Clip to circle and draw token image
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r - 1)));
      final src = Rect.fromLTWH(0, 0,
          _tokenImage!.width.toDouble(), _tokenImage!.height.toDouble());
      canvas.drawImageRect(_tokenImage!, src,
          Rect.fromCircle(center: center, radius: r - 1), Paint());
      canvas.restore();

      // Border ring
      canvas.drawCircle(center, r - 1,
          Paint()
            ..color = _isActive ? _dangerColor : _dangerColor.withOpacity(0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _isActive ? 2.5 : 1.5);
    } else {
      _renderPlaceholder(canvas, center, r);
    }

    // Action pips
    _renderActionPips(canvas, r);
  }

  void _renderPlaceholder(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(center, r,
        Paint()..color = _dangerColor.withOpacity(_isActive ? 0.2 : 0.1));
    canvas.drawCircle(center, r,
        Paint()
          ..color = _isActive ? _dangerColor : _dangerColor.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = _isActive ? 2 : 1.5);

    final icon = _iconFor(player.definitionId);
    final tp = TextPainter(
      text: TextSpan(text: icon,
          style: TextStyle(
            color: _isActive ? _dangerColor : _dangerColor.withOpacity(0.7),
            fontSize: 16, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _renderActionPips(Canvas canvas, double r) {
    for (var i = 0; i < 3; i++) {
      final filled = i < player.actionsRemaining;
      canvas.drawCircle(
        Offset(r - 8 + i * 8.0, _tokenSize - 5),
        2.5,
        Paint()..color = filled ? _dangerColor : _dangerColor.withOpacity(0.2),
      );
    }
  }

  static String _iconFor(String defId) {
    if (defId.contains('scout'))    return '◈';
    if (defId.contains('engineer')) return '⚙';
    if (defId.contains('medic'))    return '✚';
    if (defId.contains('soldier'))  return '◆';
    return '?';
  }

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
