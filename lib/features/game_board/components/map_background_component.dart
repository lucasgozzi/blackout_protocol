import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MapBackgroundComponent extends PositionComponent {
  final String mapId;
  ui.Image? _image;

  MapBackgroundComponent({
    required this.mapId,
    required Vector2 size,
  }) : super(position: Vector2.zero(), size: size);

  @override
  Future<void> onLoad() async {
    try {
      final data  = await rootBundle.load('assets/maps/$mapId.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _image = frame.image;
    } catch (e) {
      // ignore: avoid_print
      print('[MapBg] Failed to load $mapId: $e');
    }
  }

  @override
  void render(Canvas canvas) {
    if (_image == null) return;
    final src = Rect.fromLTWH(0, 0, _image!.width.toDouble(), _image!.height.toDouble());
    canvas.drawImageRect(_image!, src, size.toRect(), Paint());
  }
}
