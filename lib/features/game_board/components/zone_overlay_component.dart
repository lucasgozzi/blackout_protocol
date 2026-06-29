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
  int           _enemyCount   = 0;
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
    required int enemyCount,
    required bool hasObjective,
    required bool isSpawnZone,
  }) {
    _enemyCount   = enemyCount;
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

    // ---- Enemy counter — large badge bottom-left ----
    if (_enemyCount > 0) {
      final color = _enemyCount >= 3 ? const Color(0xFFFF2222) : const Color(0xFFFF8800);
      final bg    = _enemyCount >= 3 ? const Color(0xCC330000) : const Color(0xCC221100);
      final label = '✕$_enemyCount';
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(
          color: color,
          fontSize: size.x * 0.25,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeW = tp.width + 10;
      final badgeH = tp.height + 6;
      final badgeX = 4.0;
      final badgeY = size.y - badgeH - 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH), const Radius.circular(4)),
        Paint()..color = bg);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH), const Radius.circular(4)),
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.2);
      tp.paint(canvas, Offset(badgeX + 5, badgeY + 3));
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
