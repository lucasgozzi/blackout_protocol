import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/enemy.dart';
import '../../core/models/spawn_event.dart';

class SpawnAnimationOverlay extends ConsumerStatefulWidget {
  final List<SpawnEvent> events;
  final VoidCallback onComplete;

  const SpawnAnimationOverlay({
    super.key,
    required this.events,
    required this.onComplete,
  });

  @override
  ConsumerState<SpawnAnimationOverlay> createState() => _SpawnAnimationOverlayState();
}

class _SpawnAnimationOverlayState extends ConsumerState<SpawnAnimationOverlay>
    with TickerProviderStateMixin {
  late List<AnimationController> _cardControllers;
  late AnimationController _tokenController;
  bool _showTokens = false;

  static const _cardDelay    = Duration(milliseconds: 350);
  static const _cardDuration = Duration(milliseconds: 500);
  static const _tokenDelay   = Duration(milliseconds: 300);
  static const _tokenDuration = Duration(milliseconds: 700);
  static const _holdDuration  = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();

    _cardControllers = List.generate(widget.events.length, (i) =>
        AnimationController(vsync: this, duration: _cardDuration));

    _tokenController = AnimationController(vsync: this, duration: _tokenDuration);

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Stagger card flips.
    for (var i = 0; i < _cardControllers.length; i++) {
      await Future.delayed(i == 0 ? const Duration(milliseconds: 200) : _cardDelay);
      if (!mounted) return;
      _cardControllers[i].forward();
    }

    // Brief hold so player can read the cards.
    await Future.delayed(_holdDuration);
    if (!mounted) return;

    // Tokens materialise.
    setState(() => _showTokens = true);
    await Future.delayed(_tokenDelay);
    if (!mounted) return;
    _tokenController.forward();

    // Final hold then dismiss.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    ref.read(gameSessionProvider.notifier).clearSpawnEvents();
    widget.onComplete();
  }

  @override
  void dispose() {
    for (final c in _cardControllers) c.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap to skip animation
      onTap: () {
        ref.read(gameSessionProvider.notifier).clearSpawnEvents();
        widget.onComplete();
      },
      child: Container(
        color: Colors.black.withOpacity(0.72),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text('FASE DE SPAWN',
                    style: TextStyle(
                      color: Color(0xFFFF4444),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 4,
                    )),
              ),

              // Cards row
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: List.generate(widget.events.length, (i) =>
                    _SpawnCard(
                      event: widget.events[i],
                      controller: _cardControllers[i],
                      showToken: _showTokens,
                      tokenController: _tokenController,
                    )),
              ),

              const SizedBox(height: 32),
              const Text('toque para pular',
                  style: TextStyle(color: Color(0xFF444444),
                      fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpawnCard extends StatelessWidget {
  final SpawnEvent event;
  final AnimationController controller;
  final bool showToken;
  final AnimationController tokenController;

  const _SpawnCard({
    required this.event,
    required this.controller,
    required this.showToken,
    required this.tokenController,
  });

  static Color _tierColor(EnemyTier t) => switch (t) {
    EnemyTier.walker      => const Color(0xFFFF8800),
    EnemyTier.runner      => const Color(0xFFFFDD00),
    EnemyTier.fatty       => const Color(0xFFFF4444),
    EnemyTier.abomination => const Color(0xFFFF0088),
  };

  static String _tierLabel(EnemyTier t) => switch (t) {
    EnemyTier.walker      => 'WALKER',
    EnemyTier.runner      => 'RUNNER',
    EnemyTier.fatty       => 'FATTY',
    EnemyTier.abomination => 'ABOMINAÇÃO',
  };

  static String _tierIcon(EnemyTier t) => switch (t) {
    EnemyTier.walker      => '🤖',
    EnemyTier.runner      => '⚡',
    EnemyTier.fatty       => '💀',
    EnemyTier.abomination => '☠️',
  };

  @override
  Widget build(BuildContext context) {
    final color = _tierColor(event.tier);

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Card flip: 0→0.5 = back face, 0.5→1 = front face
        final angle = controller.value * pi;
        final isFront = controller.value > 0.5;
        final displayAngle = isFront ? angle - pi : angle;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(displayAngle),
          child: isFront ? _frontFace(color) : _backFace(),
        );
      },
    );
  }

  Widget _backFace() {
    return Container(
      width: 140, height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333355), width: 2),
      ),
      child: Center(
        child: Text('☠', style: TextStyle(
            fontSize: 48, color: const Color(0xFF222244))),
      ),
    );
  }

  Widget _frontFace(Color color) {
    return Container(
      width: 140, height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(
          color: color.withOpacity(0.4),
          blurRadius: 16, spreadRadius: 2,
        )],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Tier badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.6), width: 0.5),
            ),
            child: Text(_tierLabel(event.tier),
                style: TextStyle(color: color, fontSize: 9,
                    fontFamily: 'monospace', fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),

          // Enemy icon / token
          _EnemyTokenWidget(
            event: event,
            showToken: showToken,
            tokenController: tokenController,
            color: color,
          ),

          // Count + name
          Column(children: [
            Text('${event.count}×',
                style: const TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text(event.enemyName,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(color: color, fontSize: 10,
                    fontFamily: 'monospace', letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(event.zoneName,
                style: const TextStyle(color: Color(0xFF555566),
                    fontSize: 9, fontFamily: 'monospace')),
          ]),
        ],
      ),
    );
  }
}

class _EnemyTokenWidget extends StatelessWidget {
  final SpawnEvent event;
  final bool showToken;
  final AnimationController tokenController;
  final Color color;

  const _EnemyTokenWidget({
    required this.event,
    required this.showToken,
    required this.tokenController,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!showToken) {
      // Placeholder ring pulsing
      return _PulsingRing(color: color, size: 64);
    }

    return AnimatedBuilder(
      animation: tokenController,
      builder: (_, __) {
        final scale  = Curves.elasticOut.transform(tokenController.value.clamp(0.0, 1.0));
        final opacity = tokenController.value.clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 64, height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glow ring
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.15),
                      border: Border.all(color: color, width: 2),
                      boxShadow: [BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 12, spreadRadius: 2,
                      )],
                    ),
                  ),
                  // Token image or fallback icon
                  ClipOval(
                    child: Image.asset(
                      'assets/sprites/enemies/${event.enemyId}_token.png',
                      width: 60, height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Text(
                        _SpawnCard._tierIcon(event.tier),
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingRing({required this.color, required this.size});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.05 + _ctrl.value * 0.1),
          border: Border.all(
            color: widget.color.withOpacity(0.3 + _ctrl.value * 0.4),
            width: 2,
          ),
        ),
        child: Center(
          child: Text('?', style: TextStyle(
              color: widget.color.withOpacity(0.4 + _ctrl.value * 0.4),
              fontSize: 24, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
