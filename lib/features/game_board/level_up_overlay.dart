import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/player.dart';
import '../../core/models/skill.dart';

class LevelUpEvent {
  final String playerName;
  final DangerLevel newLevel;
  final List<SkillDefinition> unlockedSkills;

  const LevelUpEvent({
    required this.playerName,
    required this.newLevel,
    required this.unlockedSkills,
  });
}

class LevelUpOverlay extends StatefulWidget {
  final LevelUpEvent event;
  final VoidCallback onDismiss;

  const LevelUpOverlay({super.key, required this.event, required this.onDismiss});

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeIn;
  Timer? _timer;

  static const _levelColors = {
    DangerLevel.blue:   Color(0xFF4488FF),
    DangerLevel.yellow: Color(0xFFFFCC00),
    DangerLevel.orange: Color(0xFFFF8800),
    DangerLevel.red:    Color(0xFFFF3333),
  };

  static const _levelNames = {
    DangerLevel.blue:   'AZUL',
    DangerLevel.yellow: 'AMARELO',
    DangerLevel.orange: 'LARANJA',
    DangerLevel.red:    'VERMELHO',
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColors[widget.event.newLevel]!;
    final levelName = _levelNames[widget.event.newLevel]!;

    return Positioned(
      top: 80,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fadeIn,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'NÍVEL $levelName',
                      style: TextStyle(
                        color: color,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '— ${widget.event.playerName.toUpperCase()}',
                      style: const TextStyle(
                        color: Color(0xFF666677),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (widget.event.unlockedSkills.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...widget.event.unlockedSkills.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(Icons.auto_awesome, color: color, size: 11),
                        const SizedBox(width: 6),
                        Text(
                          s.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.description,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF888899),
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
