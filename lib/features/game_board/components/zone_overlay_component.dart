import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../../../core/models/zone.dart';

enum ZoneHighlight { none, selected, reachable, attack, objective, door, doorClosed }

class ZoneOverlayComponent extends PositionComponent with TapCallbacks {
  final String zoneId;
  final String zoneName;
  final ZoneType zoneType;
  final VoidCallback onTap;

  ZoneHighlight _highlight    = ZoneHighlight.none;
  bool          _hasObjective = false;
  bool          _isSpawnZone  = false;

  ZoneOverlayComponent({
    required this.zoneId,
    required this.zoneName,
    required this.zoneType,
    required Vector2 position,
    required Vector2 size,
    required this.onTap,
  }) : super(position: position, size: size);

  void setHighlight(ZoneHighlight h) => _highlight = h;

  void setZoneInfo({
    required bool hasObjective,
    required bool isSpawnZone,
  }) {
    _hasObjective = hasObjective;
    _isSpawnZone  = isSpawnZone;
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();

    // Always draw a subtle zone border so zones are visible
    final borderColor = switch (zoneType) {
      ZoneType.street     => const Color(0xFF2A2A44),
      ZoneType.extraction => const Color(0xFF1A3A1A),
      ZoneType.indoor     => const Color(0xFF222232),
      ZoneType.outdoor    => const Color(0xFF1A2A1A),
    };

    // Highlight fill
    if (_highlight != ZoneHighlight.none) {
      final fillColor = switch (_highlight) {
        ZoneHighlight.reachable  => const Color(0x3300AAFF),
        ZoneHighlight.attack     => const Color(0x44FF3333),
        ZoneHighlight.objective  => const Color(0x44FFAA00),
        ZoneHighlight.selected   => const Color(0x3300FF88),
        ZoneHighlight.door       => const Color(0x44AA44FF),
        ZoneHighlight.doorClosed => const Color(0x1AAA44FF),
        ZoneHighlight.none       => Colors.transparent,
      };
      canvas.drawRect(rect.deflate(2), Paint()..color = fillColor);

      // Thick highlight border
      final strokeColor = switch (_highlight) {
        ZoneHighlight.reachable  => const Color(0xAA00AAFF),
        ZoneHighlight.attack     => const Color(0xAAFF3333),
        ZoneHighlight.objective  => const Color(0xAAFFAA00),
        ZoneHighlight.selected   => const Color(0xAA00FF88),
        ZoneHighlight.door       => const Color(0xAAAA44FF),
        ZoneHighlight.doorClosed => const Color(0x55AA44FF),
        ZoneHighlight.none       => Colors.transparent,
      };
      canvas.drawRect(rect.deflate(2), Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _highlight == ZoneHighlight.doorClosed ? 1.5 : 2.5);
    } else {
      // Subtle zone outline always visible
      canvas.drawRect(rect.deflate(1), Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }

    // Extraction zone marker
    if (zoneType == ZoneType.extraction) {
      canvas.drawRect(rect.deflate(4), Paint()
        ..color = const Color(0x2200FF44)
        ..style = PaintingStyle.fill);
      canvas.drawRect(rect.deflate(4), Paint()
        ..color = const Color(0x8800FF44)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    // ---- Spawn zone marker — skull top-right corner ----
    if (_isSpawnZone) {
      final tp = TextPainter(
        text: TextSpan(text: '☠', style: TextStyle(
          fontSize: size.x * 0.28,
          color: const Color(0xDDFF3333),
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.x - tp.width - 4, 4));
    }

    // ---- Objective marker (pulsing box, bottom-left) ----
    if (_hasObjective) {
      final tp = TextPainter(
        text: TextSpan(text: '📦', style: TextStyle(fontSize: size.x * 0.18)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, size.y - tp.height - 4));
    }

    // Zone name (small, subtle — only on highlighted)
    if (_highlight != ZoneHighlight.none) {
      final color = switch (_highlight) {
        ZoneHighlight.reachable  => const Color(0xFF00AAFF),
        ZoneHighlight.attack     => const Color(0xFFFF4444),
        ZoneHighlight.objective  => const Color(0xFFFFAA00),
        ZoneHighlight.selected   => const Color(0xFF00FF88),
        ZoneHighlight.door       => const Color(0xFFAA66FF),
        ZoneHighlight.doorClosed => const Color(0xFF7744AA),
        ZoneHighlight.none       => Colors.transparent,
      };
      // Door icon
      if (_highlight == ZoneHighlight.door || _highlight == ZoneHighlight.doorClosed) {
        final icon = TextPainter(
          text: TextSpan(text: '🚪',
              style: TextStyle(fontSize: size.x * 0.25, color: color)),
          textDirection: TextDirection.ltr,
        )..layout();
        icon.paint(canvas, Offset(size.x / 2 - icon.width / 2, size.y / 2 - icon.height / 2));
      }
      final tp = TextPainter(
        text: TextSpan(text: zoneName,
            style: TextStyle(color: color.withOpacity(0.9), fontSize: 9,
                fontFamily: 'monospace', letterSpacing: 0.5)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.x - 8);
      tp.paint(canvas,
          Offset(size.x / 2 - tp.width / 2, size.y / 2 - tp.height / 2));
    }
  }

  @override
  void onTapDown(TapDownEvent event) => onTap();
}
