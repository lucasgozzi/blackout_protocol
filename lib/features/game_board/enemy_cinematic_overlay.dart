import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine/enemy_turn_script.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/enemy.dart';
import 'game_board_game.dart';

/// Drives the camera through each step of the enemy phase and shows
/// contextual HUD overlays (spawn cards, move/attack banners).
class EnemyCinematicOverlay extends ConsumerStatefulWidget {
  final EnemyTurnScript script;
  final GameBoardGame   game;
  final VoidCallback    onComplete;

  const EnemyCinematicOverlay({
    super.key,
    required this.script,
    required this.game,
    required this.onComplete,
  });

  @override
  ConsumerState<EnemyCinematicOverlay> createState() =>
      _EnemyCinematicOverlayState();
}

class _EnemyCinematicOverlayState extends ConsumerState<EnemyCinematicOverlay>
    with SingleTickerProviderStateMixin {
  int  _stepIndex        = 0;
  bool _skipped          = false;
  bool _waitingForPlayer = false; // true while paused on elimination panel

  EnemyTurnStep? get _current =>
      _stepIndex < widget.script.steps.length
          ? widget.script.steps[_stepIndex]
          : null;

  @override
  void initState() {
    super.initState();
    // Freeze enemy repositioning so cinematic slides aren't overridden.
    widget.game.freezeEnemySync = true;
    _runNext();
  }

  Future<void> _runNext() async {
    if (_skipped || !mounted) { _finish(); return; }
    final step = _current;
    if (step == null) { _finish(); return; }

    final (wx, wy) = _worldPosOf(step);
    await widget.game.animateCameraTo(wx.toDouble(), wy.toDouble(), ms: 450);
    if (_skipped || !mounted) { _finish(); return; }

    // Group move: reset enemies to origin, show trails, slide in parallel.
    if (step is EnemyGroupMoveStep) {
      // Put every enemy back at its FROM position before sliding.
      for (final m in step.moves) {
        final from = widget.game.worldPosForZone(m.fromZoneId);
        widget.game.placeEnemyAt(m.instanceId, from.x, from.y);
      }
      widget.game.showGroupTrails(step.moves.map((m) {
        final from = widget.game.worldPosForZone(m.fromZoneId);
        final to   = widget.game.worldPosForZone(m.toZoneId);
        return (instanceId: m.instanceId, fx: from.x, fy: from.y, tx: to.x, ty: to.y);
      }).toList());
      await widget.game.slideGroupTo(step.moves.map((m) {
        final to = widget.game.worldPosForZone(m.toZoneId);
        return (instanceId: m.instanceId, tx: to.x, ty: to.y);
      }).toList());
      if (_skipped || !mounted) { _finish(); return; }
      await Future.delayed(const Duration(milliseconds: 350));
      widget.game.clearGroupTrails();
    }

    // For attack steps that eliminate a player: pause and wait for tap.
    if (step is EnemyAttackStep && step.playerEliminated) {
      setState(() => _waitingForPlayer = true);
      return; // _advanceFromElimination() resumes when player taps
    }

    final holdMs = switch (step) {
      SpawnStep()            => 1600,
      EnemyAttackStep()      => 1400,
      EnemyGroupMoveStep()   => 200,
      EnemyMoveStep()        => 200,
    };
    await Future.delayed(Duration(milliseconds: holdMs));
    if (_skipped || !mounted) { _finish(); return; }

    setState(() => _stepIndex++);
    _runNext();
  }

  void _advanceFromElimination() {
    if (!mounted) return;
    setState(() {
      _waitingForPlayer = false;
      _stepIndex++;
    });
    _runNext();
  }

  void _skip() {
    widget.game.clearMovementTrail();
    widget.game.clearGroupTrails();
    _skipped = true;
    _finish();
  }

  void _finish() {
    if (!mounted) return;
    // Unfreeze so normal sync resumes positioning enemies correctly.
    widget.game.freezeEnemySync = false;
    ref.read(gameSessionProvider.notifier).clearCinematic();
    widget.onComplete();
  }

  (double, double) _worldPosOf(EnemyTurnStep step) {
    final zoneId = switch (step) {
      SpawnStep s          => s.zoneId,
      EnemyMoveStep s      => s.toZoneId,
      EnemyGroupMoveStep s => s.toZoneId,
      EnemyAttackStep s    => s.zoneId,
    };
    final v = widget.game.worldPosForZone(zoneId);
    return (v.x, v.y);
  }

  @override
  Widget build(BuildContext context) {
    final step = _current;
    if (step == null) return const SizedBox.shrink();

    // Elimination pause — full overlay, player must tap to continue.
    if (_waitingForPlayer && step is EnemyAttackStep) {
      return _EliminationPanel(
        step: step,
        onContinue: _advanceFromElimination,
      );
    }

    return GestureDetector(
      onTap: _skip,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // Info chip — not shown for spawns (the card already shows everything)
          if (step is! SpawnStep)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 48, right: 48,
              child: _StepChip(step: step),
            ),
          // Spawn card — top left, compact
          if (step is SpawnStep)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 16,
              child: _SpawnCardWidget(step: step),
            ),
          // Skip hint — bottom right, very faint
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            right: 16,
            child: const Text('toque para pular',
              style: TextStyle(
                color: Color(0x99FFFFFF), fontSize: 12,
                fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

// ---- Step chip (single top-center info badge) ----

class _StepChip extends StatefulWidget {
  final EnemyTurnStep step;
  const _StepChip({required this.step});

  @override
  State<_StepChip> createState() => _StepChipState();
}

class _StepChipState extends State<_StepChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_StepChip old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;

    final (icon, title, subtitle, color) = switch (step) {
      SpawnStep s => (
        '⚠',
        'SPAWN',
        '${s.count}× ${s.enemyName.toUpperCase()}',
        const Color(0xFFFF4444),
      ),
      EnemyGroupMoveStep s => (
        '⚡',
        s.enemyName.toUpperCase(),
        '${s.moves.length}× SE MOVE',
        const Color(0xFFFF8800),
      ),
      EnemyMoveStep s => (
        '⚡',
        s.enemyName.toUpperCase(),
        'SE MOVE',
        const Color(0xFFFF8800),
      ),
      EnemyAttackStep s => (
        s.playerEliminated ? '💀' : s.playerWounded ? '⚠' : '⚡',
        s.enemyName.toUpperCase(),
        s.playerEliminated
            ? '${_opName(s.targetName)} ELIMINADO'
            : s.playerWounded
                ? '${_opName(s.targetName)} FERIDO'
                : 'ATACA ${_opName(s.targetName)}',
        s.playerEliminated
            ? const Color(0xFFFF2222)
            : s.playerWounded
                ? const Color(0xFFFF6600)
                : const Color(0xFFFF4444),
      ),
    };

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Transform.translate(
          offset: Offset(0, -8 * (1 - _anim.value)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xEE0A0A14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 12, spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      color: color,
                      fontSize: 13, fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, letterSpacing: 0.5,
                    )),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 12, fontFamily: 'monospace',
                      )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _opName(String id) =>
      id.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}

// ---- Spawn card (shown centered) ----

class _SpawnCardWidget extends StatefulWidget {
  final SpawnStep step;
  const _SpawnCardWidget({required this.step});

  @override
  State<_SpawnCardWidget> createState() => _SpawnCardWidgetState();
}

class _SpawnCardWidgetState extends State<_SpawnCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  static Color _tierColor(EnemyTier t) => switch (t) {
    EnemyTier.walker      => const Color(0xFFFF8800),
    EnemyTier.runner      => const Color(0xFFFFDD00),
    EnemyTier.fatty       => const Color(0xFFFF4444),
    EnemyTier.abomination => const Color(0xFFFF0088),
  };

  static Color _tierColorOnLight(EnemyTier t) => switch (t) {
    EnemyTier.walker      => const Color(0xFFCC6600),
    EnemyTier.runner      => const Color(0xFFAA8800),
    EnemyTier.fatty       => const Color(0xFFCC2222),
    EnemyTier.abomination => const Color(0xFFAA0066),
  };

  static String _tierLabel(EnemyTier t) => switch (t) {
    EnemyTier.walker      => 'WALKER',
    EnemyTier.runner      => 'RUNNER',
    EnemyTier.fatty       => 'FATTY',
    EnemyTier.abomination => 'ABOMINAÇÃO',
  };

  @override
  Widget build(BuildContext context) {
    final s     = widget.step;
    final color = _tierColor(s.tier);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final angle = _ctrl.value * math.pi;
        final isFront = _ctrl.value > 0.5;
        final displayAngle = isFront ? angle - math.pi : angle;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(displayAngle),
          child: isFront ? _front(s, color) : _back(),
        );
      },
    );
  }

  Widget _back() => Container(
    width: 110, height: 148,
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0F8),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF333355), width: 2),
    ),
    child: const Center(
      child: Text('☠', style: TextStyle(fontSize: 36, color: Color(0xFFCCCCDD))),
    ),
  );

  Widget _front(SpawnStep s, Color color) => Container(
    width: 110, height: 148,
    decoration: BoxDecoration(
      color: const Color(0xFFF8F8FF),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color, width: 2),
      boxShadow: [BoxShadow(
        color: color.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 3)],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
          ),
          child: Text(_tierLabel(s.tier),
            style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace',
                fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
        // Token image or fallback
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [BoxShadow(
              color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)],
          ),
          child: ClipOval(child: Image.asset(
            'assets/sprites/enemies/${s.enemyId}_token.png',
            width: 44, height: 44, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(
              switch (s.tier) {
                EnemyTier.walker      => '🤖',
                EnemyTier.runner      => '⚡',
                EnemyTier.fatty       => '💀',
                EnemyTier.abomination => '☠️',
              },
              style: const TextStyle(fontSize: 22),
              textAlign: TextAlign.center,
            ),
          )),
        ),
        Column(children: [
          Text('${s.count}×',
            style: const TextStyle(color: Color(0xFF111122), fontSize: 16,
                fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(s.enemyName,
            textAlign: TextAlign.center,
            style: TextStyle(color: _tierColorOnLight(s.tier), fontSize: 11,
                fontFamily: 'monospace', letterSpacing: 0.5)),
          Text(s.zoneName,
            style: const TextStyle(color: Color(0xFF777788),
                fontSize: 10, fontFamily: 'monospace')),
        ]),
      ],
    ),
  );
}

// ---- Elimination panel ----

class _EliminationPanel extends StatefulWidget {
  final EnemyAttackStep step;
  final VoidCallback onContinue;
  const _EliminationPanel({required this.step, required this.onContinue});

  @override
  State<_EliminationPanel> createState() => _EliminationPanelState();
}

class _EliminationPanelState extends State<_EliminationPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF2222);

    return GestureDetector(
      onTap: widget.onContinue,
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF100808),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: red, width: 2),
                boxShadow: [BoxShadow(
                    color: red.withValues(alpha: 0.4),
                    blurRadius: 32, spreadRadius: 4)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.close, color: red, size: 48),
                const SizedBox(height: 16),
                const Text('OPERADOR ELIMINADO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: red, fontSize: 16, fontFamily: 'monospace',
                    fontWeight: FontWeight.bold, letterSpacing: 3,
                  )),
                const SizedBox(height: 10),
                Text(
                  widget.step.targetName.replaceAll('_', ' ').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 20,
                    fontFamily: 'monospace', fontWeight: FontWeight.bold,
                  )),
                const SizedBox(height: 6),
                Text(
                  'eliminado por ${widget.step.enemyName}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: red.withValues(alpha: 0.7),
                    fontSize: 12, fontFamily: 'monospace',
                  )),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: red.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('toque para continuar',
                    style: TextStyle(
                      color: Color(0xFFAA4444), fontSize: 12,
                      fontFamily: 'monospace', letterSpacing: 1,
                    )),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
