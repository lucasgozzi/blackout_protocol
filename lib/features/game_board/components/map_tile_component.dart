import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MapTileComponent extends PositionComponent with TapCallbacks {
  final String tileId;
  final String imageName;
  final void Function(double localX, double localY) onTap;

  ui.Image? _image;
  bool _loaded = false;

  MapTileComponent({
    required this.tileId,
    required this.imageName,
    required Vector2 position,
    required Vector2 size,
    required this.onTap,
  }) : super(position: position, size: size);

  @override
  Future<void> onLoad() async {
    try {
      final path = 'assets/sprites/tiles/$imageName.png';
      final data  = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _image  = frame.image;
      _loaded = true;
      // ignore: avoid_print
      print('[Tile] Loaded $imageName (${_image!.width}x${_image!.height})');
    } catch (e) {
      // ignore: avoid_print
      print('[Tile] Failed to load $imageName: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();

    if (_loaded && _image != null) {
      final src = Rect.fromLTWH(0, 0, _image!.width.toDouble(), _image!.height.toDouble());
      canvas.drawImageRect(_image!, src, rect, Paint());
    } else {
      // Placeholder while images not generated yet
      _renderPlaceholder(canvas, rect);
    }
  }

  void _renderPlaceholder(Canvas canvas, Rect rect) {
    // Tile background by type
    final bgColor = switch (imageName) {
      String s when s.contains('street')     => const Color(0xFF1C1C2A),
      String s when s.contains('crossroads') => const Color(0xFF1E1E2E),
      String s when s.contains('plaza')      => const Color(0xFF1A1A28),
      String s when s.contains('extraction') => const Color(0xFF0A1A0A),
      String s when s.contains('garage')     => const Color(0xFF1A1820),
      _                                      => const Color(0xFF141420),
    };
    canvas.drawRect(rect, Paint()..color = bgColor);

    // Grid pattern to hint floor tiles
    final gridPaint = Paint()
      ..color = bgColor.withOpacity(0.5).withBlue((bgColor.blue + 20).clamp(0, 255))
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const gridSize = 20.0;
    for (var x = 0.0; x <= rect.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, rect.height), gridPaint);
    }
    for (var y = 0.0; y <= rect.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(rect.width, y), gridPaint);
    }

    // Tile border
    canvas.drawRect(rect, Paint()
      ..color = const Color(0xFF2A2A3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // Tile name label
    final name = imageName.replaceAll('tile_', '').replaceAll('_', ' ').toUpperCase();
    final tp = TextPainter(
      text: TextSpan(text: name,
          style: const TextStyle(color: Color(0xFF444466), fontSize: 11,
              fontFamily: 'monospace', letterSpacing: 1)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width - 8);
    tp.paint(canvas, Offset(rect.width / 2 - tp.width / 2,
                             rect.height / 2 - tp.height / 2));
  }

  @override
  void onTapDown(TapDownEvent event) {
    onTap(event.localPosition.x, event.localPosition.y);
  }
}
