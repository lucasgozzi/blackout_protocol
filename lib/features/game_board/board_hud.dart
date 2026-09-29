import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/game_state.dart';
import '../../core/models/player.dart';
import '../../core/models/weapon.dart';
import '../dashboard/survivor_dashboard.dart';
import 'game_board_game.dart';

class BoardHud extends ConsumerWidget {
  final GameBoardGame game;
  const BoardHud({super.key, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session      = ref.watch(gameSessionProvider);
    final pendingLoot  = ref.watch(pendingLootProvider);
    final woundedId    = ref.watch(lastWoundedPlayerProvider);
    if (session == null) return const SizedBox.shrink();

    final g = session.game;
    final activePlayer = g.players.firstWhere(
      (p) => p.playerId == g.activePlayerId,
      orElse: () => g.players.first,
    );

    return Stack(
      children: [
        // Main layout column
        Column(
          children: [
            _TopBar(game: g, mission: session.mission),
            const Spacer(),
            _ActionBar(gameState: g, activePlayer: activePlayer, flameGame: game, ref: ref),
          ],
        ),
        // Combat log — top center, compact, doesn't block the map
        Positioned(
          top: MediaQuery.of(context).padding.top + 56,
          left: 60, right: 60,
          child: _CombatLog(ref: ref, game: g),
        ),
        // FAB overlay — Positioned on the full Stack so taps always register
        _PlayerFab(gameState: g, activePlayer: activePlayer, ref: ref),

        // Zoom controls
        _ZoomControls(game: game),

        // Damage flash — fires when any player is wounded
        if (woundedId != null)
          _DamageFlash(
            woundedPlayerId: woundedId,
            players: g.players,
            onDone: () => ref.read(gameSessionProvider.notifier).clearWounded(),
          ),

        // Loot placement panel — anchored at bottom, does NOT cover the board
        if (pendingLoot != null)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _LootChoicePanel(
              lootId: pendingLoot.lootId,
              player: g.players.firstWhere(
                (p) => p.playerId == pendingLoot.playerId,
                orElse: () => g.players.first,
              ),
            ),
          ),
      ],
    );
  }
}

// ---- Top bar ----

class _TopBar extends StatelessWidget {
  final GameState game;
  final dynamic mission;
  const _TopBar({required this.game, required this.mission});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 52, 12, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xEE050510), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          _chip('ROUND ${game.round}', const Color(0xFF00AAFF)),
          const SizedBox(width: 8),
          _chip(
            game.phase == GamePhase.playerTurn ? 'SEU TURNO' : game.phase.name.toUpperCase(),
            game.phase == GamePhase.playerTurn ? const Color(0xFF00FF88) : const Color(0xFFFFAA00),
          ),
          const Spacer(),
          _alertWidget(game.alertLevel, mission.maxAlertLevel),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.5), width: 0.5),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 13, fontFamily: 'monospace', letterSpacing: 0.5)),
  );

  Widget _alertWidget(int level, int max) {
    final f = level / max;
    final color = f >= 0.8 ? const Color(0xFFFF4444) : f >= 0.5 ? const Color(0xFFFFAA00) : const Color(0xFF00AAFF);
    return Row(children: [
      Icon(Icons.trending_up, color: color, size: 14),
      const SizedBox(width: 4),
      Text('Spawn $level', style: TextStyle(color: color, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
    ]);
  }
}

// ---- Combat log & event log ----

class _CombatLog extends ConsumerWidget {
  final WidgetRef ref;
  final GameState game;
  const _CombatLog({required this.ref, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final combatLog = ref.watch(lastCombatLogProvider);
    if (combatLog != null) return _DiceRollToast(log: combatLog, ref: ref);
    return const SizedBox.shrink();
  }
}

// ---- Dice Roll Toast ----

class _DiceRollToast extends StatefulWidget {
  final ZoneCombatLog log;
  final WidgetRef ref;
  const _DiceRollToast({required this.log, required this.ref});

  @override
  State<_DiceRollToast> createState() => _DiceRollToastState();
}

class _DiceRollToastState extends State<_DiceRollToast>
    with TickerProviderStateMixin {
  static const _hitThreshold = 4;
  static const _rollDuration  = Duration(milliseconds: 600);
  static const _staggerMs     = 100;
  static const _holdDuration  = Duration(seconds: 3);

  // Per-die: spin controller + settled flag
  late List<AnimationController> _spinCtrl;
  late List<Animation<double>>   _spin;
  late List<bool>                _settled;

  // Result reveal
  late AnimationController _resultCtrl;
  late Animation<double>   _resultAnim;

  // Toast fade-out
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  // Random face shown while spinning
  final List<int> _spinFace = [];

  @override
  void initState() {
    super.initState();
    final n = widget.log.rolls.length;

    _spinCtrl = List.generate(n, (_) => AnimationController(
        vsync: this, duration: _rollDuration));
    _spin     = _spinCtrl.map((c) =>
        CurvedAnimation(parent: c, curve: Curves.easeOut)).toList();
    _settled  = List.filled(n, false);
    _spinFace.addAll(List.generate(n, (i) => (i % 6) + 1));

    _resultCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _resultAnim = CurvedAnimation(parent: _resultCtrl,
        curve: Curves.easeOutBack);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Stagger die settlements
    for (var i = 0; i < _spinCtrl.length; i++) {
      await Future.delayed(Duration(milliseconds: i * _staggerMs));
      if (!mounted) return;
      _spinCtrl[i].forward();
      _spinCtrl[i].addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _settled[i] = true);
        }
      });
    }

    // Wait for last die + brief hold
    await Future.delayed(Duration(
        milliseconds: (_spinCtrl.length - 1) * _staggerMs) + _rollDuration);
    if (!mounted) return;

    _resultCtrl.forward();
    await Future.delayed(_holdDuration);
    if (!mounted) return;

    _fadeCtrl.forward().then((_) => _dismiss());
  }

  void _dismiss() {
    if (!mounted) return;
    widget.ref.read(gameSessionProvider.notifier).clearCombatLog();
  }

  @override
  void dispose() {
    for (final c in _spinCtrl) c.dispose();
    _resultCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;

    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (_, child) => Opacity(
        opacity: 1 - _fadeAnim.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: _dismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xF00A0A16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: log.eliminatedEnemyIds.isNotEmpty
                  ? const Color(0xFF00FF88)
                  : log.friendlyFire
                      ? const Color(0xFFFF4444)
                      : const Color(0xFF333344),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x44000000), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dice row
              Wrap(
                spacing: 6, runSpacing: 6,
                alignment: WrapAlignment.center,
                children: List.generate(log.rolls.length, (i) =>
                    _DieWidget(
                      finalValue: log.rolls[i],
                      isHit: log.rolls[i] >= _hitThreshold,
                      settled: _settled[i],
                      spinAnim: _spin[i],
                    )),
              ),

              // Result line — slides in after dice settle
              AnimatedBuilder(
                animation: _resultAnim,
                builder: (_, __) => Opacity(
                  opacity: _resultAnim.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - _resultAnim.value)),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _ResultRow(log: log),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Single animated die ----

class _DieWidget extends StatefulWidget {
  final int finalValue;
  final bool isHit;
  final bool settled;
  final Animation<double> spinAnim;

  const _DieWidget({
    required this.finalValue,
    required this.isHit,
    required this.settled,
    required this.spinAnim,
  });

  @override
  State<_DieWidget> createState() => _DieWidgetState();
}

class _DieWidgetState extends State<_DieWidget> with TickerProviderStateMixin {
  late AnimationController _bounceCtrl;
  late Animation<double>   _bounce;
  int _displayValue = 1;
  late final _ticker = createTicker(_onTick);
  Duration _lastFaceChange = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _bounce = CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut);
    _ticker.start();
    widget.spinAnim.addStatusListener(_onSpinStatus);
  }

  void _onTick(Duration elapsed) {
    if (widget.settled) return;
    // Cycle random face every ~80ms while spinning
    if ((elapsed - _lastFaceChange).inMilliseconds > 80) {
      _lastFaceChange = elapsed;
      if (mounted) setState(() => _displayValue = (elapsed.inMilliseconds ~/ 80 % 6) + 1);
    }
  }

  void _onSpinStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed && mounted) {
      setState(() => _displayValue = widget.finalValue);
      if (widget.isHit) _bounceCtrl.forward();
    }
  }

  @override
  void dispose() {
    _ticker.stop();
    _bounceCtrl.dispose();
    widget.spinAnim.removeStatusListener(_onSpinStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settled = widget.settled;
    final isHit   = widget.isHit;

    final hitColor  = const Color(0xFF00FF88);
    const missColor = Color(0xFF555566);
    final color     = settled ? (isHit ? hitColor : missColor) : const Color(0xFF888899);

    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, __) {
        final scale = settled && isHit
            ? 1.0 + _bounce.value * 0.35
            : settled ? 0.88 : 1.0;

        return Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: settled && isHit
                  ? hitColor.withValues(alpha: 0.18)
                  : const Color(0xFF111120),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color,
                width: settled && isHit ? 2 : 1,
              ),
              boxShadow: settled && isHit
                  ? [BoxShadow(
                      color: hitColor.withValues(alpha: 0.5),
                      blurRadius: 8, spreadRadius: 1)]
                  : null,
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  color: color,
                  fontSize: settled && isHit ? 16 : 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                child: Text('$_displayValue'),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---- Result row shown after dice settle ----

class _ResultRow extends StatelessWidget {
  final ZoneCombatLog log;
  const _ResultRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final hasKills  = log.eliminatedEnemyIds.isNotEmpty;
    final hasDamage = log.hits > 0 && !hasKills;
    final noHits    = log.hits == 0;
    final ff        = log.friendlyFire;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hits + XP row
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _pill(
            '${log.hits} acerto${log.hits != 1 ? "s" : ""}',
            log.hits > 0 ? const Color(0xFF00FF88) : const Color(0xFF777788),
          ),
          if (log.xpGained > 0) ...[
            const SizedBox(width: 8),
            _pill('+${log.xpGained} XP', const Color(0xFFFFAA00)),
          ],
        ]),
        const SizedBox(height: 6),
        // Outcome
        if (hasKills)
          _line(
            '✓  ${log.eliminatedEnemyIds.length} eliminado${log.eliminatedEnemyIds.length > 1 ? "s" : ""}',
            const Color(0xFF00FF88)),
        if (hasDamage)
          _line('— dano causado', const Color(0xFFFFAA00)),
        if (noHits)
          _line('✗  sem acertos', const Color(0xFF777788)),
        if (ff)
          _line('⚠ fogo amigo', const Color(0xFFFF4444)),
        if (log.woundedSurvivorIds.isNotEmpty)
          _line(
            '⚠ ${log.woundedSurvivorIds.length} aliado${log.woundedSurvivorIds.length > 1 ? "s feridos" : " ferido"}',
            const Color(0xFFFF4444)),
      ],
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
    ),
    child: Text(label, style: TextStyle(
      color: color, fontSize: 11,
      fontFamily: 'monospace', fontWeight: FontWeight.bold,
    )),
  );

  Widget _line(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(text, textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace')),
  );
}

// ---- Action bar ----

class _ActionBar extends StatefulWidget {
  final GameState gameState;
  final PlayerState activePlayer;
  final GameBoardGame flameGame;
  final WidgetRef ref;

  const _ActionBar({required this.gameState, required this.activePlayer,
      required this.flameGame, required this.ref});

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar>
    with SingleTickerProviderStateMixin {
  ActionMode _mode     = ActionMode.none;
  bool _menuOpen       = false;
  bool _showTrade      = false;
  late AnimationController _menuCtrl;
  late Animation<double>   _menuAnim;

  @override
  void initState() {
    super.initState();
    _menuCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _menuAnim = CurvedAnimation(parent: _menuCtrl, curve: Curves.easeOutCubic);
    widget.flameGame.onActionModeChanged = (mode) {
      if (mounted) setState(() => _mode = mode);
    };
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  void _tap(ActionMode mode) {
    widget.flameGame.setActionMode(mode);
    _closeMenu();
  }

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
    if (_menuOpen) {
      _menuCtrl.forward();
    } else {
      _menuCtrl.reverse();
      _showTrade = false;
    }
  }

  void _closeMenu() {
    if (_menuOpen) {
      setState(() { _menuOpen = false; _showTrade = false; });
      _menuCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p            = widget.activePlayer;
    final isPlayerTurn = widget.gameState.phase == GamePhase.playerTurn;
    final canAct       = isPlayerTurn && p.actionsRemaining > 0;
    final canMove      = canAct && p.zonesMovedThisTurn < p.movementRange;
    final hasDoor      = widget.flameGame.hasDoorAdjacent;
    final hasAllies    = _alliesInSameZone(widget.gameState, p).isNotEmpty;

    // Build the list of secondary actions for the menu
    final menuItems = <_MenuItem>[
      _MenuItem(
        icon: Icons.gps_fixed, label: 'ATACAR',
        color: const Color(0xFFFF4444),
        enabled: canAct,
        onTap: () => _tap(ActionMode.attack),
        isActive: _mode == ActionMode.attack,
      ),
      _MenuItem(
        icon: Icons.search, label: 'BUSCAR',
        color: const Color(0xFFFFAA00),
        enabled: canAct && widget.flameGame.canSearchCurrentPosition(widget.gameState.activePlayerId),
        onTap: () {
          widget.flameGame.searchCurrentPosition(widget.gameState.activePlayerId);
          _closeMenu();
        },
      ),
      if (hasDoor) _MenuItem(
        icon: Icons.door_front_door_outlined, label: 'PORTA',
        color: const Color(0xFFAA66FF),
        enabled: canAct,
        onTap: () => _tap(ActionMode.openDoor),
        isActive: _mode == ActionMode.openDoor,
      ),
      if (hasAllies) _MenuItem(
        icon: Icons.swap_horiz, label: 'TROCAR',
        color: const Color(0xFF44DDAA),
        enabled: canAct,
        onTap: () => setState(() { _showTrade = !_showTrade; }),
        isActive: _showTrade,
      ),
    ];

    final anyMenuActive = menuItems.any((m) => m.isActive);

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12,
          MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Color(0xF0050510), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPlayerTurn)
            _WeaponStrip(player: p, ref: widget.ref, flameGame: widget.flameGame),
          const SizedBox(height: 8),

          // Floating menu pills (above bar, anchored left of AÇÕES btn)
          if (_menuOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AnimatedBuilder(
                animation: _menuAnim,
                builder: (_, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: menuItems.asMap().entries.map((e) {
                    final i    = e.key;
                    final item = e.value;
                    final delay = i / menuItems.length;
                    final t = (((_menuAnim.value - delay) / (1 - delay))
                        .clamp(0.0, 1.0));
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - t)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _MenuPill(item: item),
                        ),
                      ),
                    );
                  }).toList().reversed.toList(),
                ),
              ),
            ),

          // Bottom row: MOVER | AÇÕES | FIM TURNO
          Row(
            children: [
              if (isPlayerTurn) ...[
                // MOVER — always visible
                _primaryBtn(
                  icon: Icons.directions_walk,
                  label: 'MOVER',
                  color: const Color(0xFF00AAFF),
                  enabled: canMove,
                  active: _mode == ActionMode.move,
                  onTap: canMove ? () => _tap(ActionMode.move) : null,
                ),
                const SizedBox(width: 8),
                // AÇÕES — opens menu
                _primaryBtn(
                  icon: _menuOpen ? Icons.close : Icons.bolt,
                  label: 'AÇÕES',
                  color: anyMenuActive
                      ? menuItems.firstWhere((m) => m.isActive).color
                      : const Color(0xFFFF8800),
                  enabled: canAct,
                  active: _menuOpen || anyMenuActive,
                  onTap: canAct ? _toggleMenu : null,
                ),
                const SizedBox(width: 8),
              ],
              // FIM TURNO — always visible, fills remaining space
              Expanded(child: _endTurnBtn(isPlayerTurn)),
            ],
          ),

          // Trade panel (expands below when active)
          if (_showTrade) ...[
            const SizedBox(height: 8),
            _TradePanel(
              gameState: widget.gameState,
              ref: widget.ref,
              onClose: () => setState(() => _showTrade = false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _primaryBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required bool active,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.2)
              : const Color(0xCC0D0D1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color
                : (enabled ? color.withValues(alpha: 0.5) : const Color(0xFF444444)),
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 10)]
              : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: enabled ? color : const Color(0xFF555555), size: 26),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
              color: enabled ? color : const Color(0xFF555555),
              fontSize: 12, fontFamily: 'monospace',
              fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ]),
      ),
    );
  }

  Widget _endTurnBtn(bool isPlayerTurn) {
    final canEnd = isPlayerTurn && widget.gameState.outcome == GameOutcome.none;
    return GestureDetector(
      onTap: canEnd
          ? () {
              _closeMenu();
              widget.ref.read(gameSessionProvider.notifier).endPlayerTurn();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: canEnd
              ? const Color(0xFF00FF88).withValues(alpha: 0.12)
              : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: canEnd ? const Color(0xFF00FF88) : const Color(0xFF444444),
              width: 1.5),
        ),
        child: Text('FIM DE TURNO', textAlign: TextAlign.center,
          style: TextStyle(
            color: canEnd ? const Color(0xFF00FF88) : const Color(0xFF666666),
            fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold,
          )),
      ),
    );
  }

}

// ---- Action menu data ----

class _MenuItem {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final bool isActive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.isActive = false,
  });
}

class _MenuPill extends StatelessWidget {
  final _MenuItem item;
  const _MenuPill({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.color;
    final enabled = item.enabled;
    final active  = item.isActive;

    return GestureDetector(
      onTap: enabled ? item.onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.22)
              : const Color(0xEE0D0D1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active ? color
                : (enabled ? color.withValues(alpha: 0.55) : const Color(0xFF555555)),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(item.icon,
              color: enabled ? color : const Color(0xFF666666), size: 18),
          const SizedBox(width: 8),
          Text(item.label, style: TextStyle(
            color: enabled ? (active ? color : Colors.white) : const Color(0xFF777777),
            fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold,
          )),
          if (active) ...[
            const SizedBox(width: 6),
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ],
        ]),
      ),
    );
  }
}

// ---- Zoom controls ----

class _ZoomControls extends StatefulWidget {
  final GameBoardGame game;
  const _ZoomControls({required this.game});

  @override
  State<_ZoomControls> createState() => _ZoomControlsState();
}

class _ZoomControlsState extends State<_ZoomControls> {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomBtn(Icons.add, () => setState(() => widget.game.zoomIn())),
          const SizedBox(height: 6),
          _zoomBtn(Icons.remove, () => setState(() => widget.game.zoomOut())),
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: const Color(0xCC0D0D1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF555566), width: 1),
        ),
        child: Icon(icon, color: const Color(0xFFBBBBCC), size: 22),
      ),
    );
  }
}

// ---- Player FAB (Positioned in BoardHud Stack) ----

class _PlayerFab extends StatefulWidget {
  final GameState gameState;
  final PlayerState activePlayer;
  final WidgetRef ref;

  const _PlayerFab({required this.gameState, required this.activePlayer, required this.ref});

  @override
  State<_PlayerFab> createState() => _PlayerFabState();
}

class _PlayerFabState extends State<_PlayerFab>
    with SingleTickerProviderStateMixin {
  bool _showInventory  = false;
  bool _showDashboard  = false;
  bool _showMenu       = false;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  static Color _dangerColor(PlayerState p) => switch (p.dangerLevel) {
    DangerLevel.blue   => const Color(0xFF00FF88),
    DangerLevel.yellow => const Color(0xFFFFDD00),
    DangerLevel.orange => const Color(0xFFFF8800),
    DangerLevel.red    => const Color(0xFFFF2222),
  };

  @override
  Widget build(BuildContext context) {
    final p       = widget.activePlayer;
    final color   = _dangerColor(p);
    final wounded = p.dangerLevel != DangerLevel.blue;
    final bottom  = MediaQuery.of(context).padding.bottom + 110;

    return Positioned(
      right: 12,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Panels
          if (_showInventory)
            _InventoryFab(
              player: p,
              ref: widget.ref,
              onClose: () => setState(() => _showInventory = false),
            ),
          if (_showDashboard)
            SurvivorDashboard(
              playerId: widget.gameState.activePlayerId,
              onClose: () => setState(() => _showDashboard = false),
            ),
          if (_showMenu) ...[
            _menuItem(Icons.person_outline, 'FICHA', const Color(0xFFAA88FF),
                () => setState(() { _showDashboard = true; _showMenu = false; })),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 8),

          // FAB circle
          GestureDetector(
            onTap: () => setState(() {
              _showInventory = !_showInventory;
              _showDashboard = false;
              _showMenu      = false;
            }),
            onLongPress: () => setState(() {
              _showMenu      = !_showMenu;
              _showInventory = false;
            }),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) {
                final borderW  = wounded ? 2.0 + _pulse.value * 2.0 : 2.0;
                final glowR    = wounded ? 12.0 + _pulse.value * 10.0 : 12.0;
                final glowA    = wounded ? 0.35 + _pulse.value * 0.3 : 0.35;
                return Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: borderW),
                    boxShadow: [BoxShadow(
                        color: color.withValues(alpha: glowA),
                        blurRadius: glowR, spreadRadius: 1)],
                  ),
                  child: child,
                );
              },
              child: ClipOval(
                child: Image.asset(
                  'assets/sprites/characters/${p.definitionId}_token.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.person, color: color, size: 32),
                ),
              ),
            ),
          ),

          // Action pips
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(p.actionsRemaining.clamp(0, 3), (_) =>
              Container(width: 9, height: 9,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xEE0D0D1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12,
              fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

// ---- Weapon strip shown above action buttons ----

class _WeaponStrip extends StatefulWidget {
  final PlayerState player;
  final WidgetRef ref;
  final GameBoardGame flameGame;
  const _WeaponStrip({required this.player, required this.ref, required this.flameGame});

  @override
  State<_WeaponStrip> createState() => _WeaponStripState();
}

class _WeaponStripState extends State<_WeaponStrip> {
  @override
  Widget build(BuildContext context) {
    final catalog    = widget.ref.read(gameSessionProvider.notifier).weaponCatalog;
    final activeId   = widget.flameGame.activeWeaponId;
    final player     = widget.player;

    Widget slot(String label, String? itemId) {
      final isActive = itemId != null && itemId == activeId;
      final hasItem  = itemId != null;

      if (!hasItem) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x220D0D1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1A1A2E), width: 0.5),
          ),
          child: Text('$label  —', style: const TextStyle(
              color: Color(0xFF333344), fontSize: 12, fontFamily: 'monospace')),
        );
      }

      String name  = itemId.replaceAll('_', ' ');
      String stats = '';
      try {
        final w = catalog?.getById(itemId);
        if (w != null) { name = w.name; stats = '${w.dice}d${w.hitValue}+  ${w.damage}dmg'; }
      } catch (_) {}

      final color = isActive ? const Color(0xFFFFAA00) : const Color(0xFF00AAFF);

      return GestureDetector(
        onTap: () {
          setState(() {
            widget.flameGame.activeWeaponId =
                isActive ? null : itemId; // toggle
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFFFAA00).withOpacity(0.18)
                : const Color(0xFF00AAFF).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFFFAA00)
                  : const Color(0xFF00AAFF).withOpacity(0.4),
              width: isActive ? 1.5 : 0.8,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isActive ? Icons.check_circle : Icons.back_hand_outlined,
              color: color, size: 14,
            ),
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(
                  color: isActive ? const Color(0xFFFFAA00) : Colors.white,
                  fontSize: 12, fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
              if (stats.isNotEmpty)
                Text(stats, style: TextStyle(
                    color: color, fontSize: 11, fontFamily: 'monospace')),
            ]),
          ]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            slot('ESQ', player.equippedLeft),
            const SizedBox(width: 10),
            slot('DIR', player.equippedRight),
          ],
        ),
        if (activeId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '↑ usando esta arma no próximo ataque',
              style: const TextStyle(
                color: Color(0xFFFFAA00), fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}

// ---- Inventory FAB panel ----

class _InventoryFab extends StatefulWidget {
  final PlayerState player;
  final WidgetRef ref;
  final VoidCallback onClose;

  const _InventoryFab({required this.player, required this.ref, required this.onClose});

  @override
  State<_InventoryFab> createState() => _InventoryFabState();
}

class _InventoryFabState extends State<_InventoryFab> {
  @override
  Widget build(BuildContext context) {
    final catalog  = widget.ref.read(gameSessionProvider.notifier).weaponCatalog;
    final notifier = widget.ref.read(gameSessionProvider.notifier);
    final p        = widget.player;
    final canAct   = p.actionsRemaining > 0;

    String itemLabel(String? id) {
      if (id == null) return '—';
      try { return catalog?.getById(id).name ?? id.replaceAll('_', ' '); }
      catch (_) { return id.replaceAll('_', ' '); }
    }

    String itemStats(String? id) {
      if (id == null) return '';
      try {
        final w = catalog?.getById(id);
        if (w == null || w.dice == 0) return '';
        return '${w.dice}d${w.hitValue}+  ${w.damage}dmg';
      } catch (_) { return ''; }
    }

    // Hand drop target
    Widget handDropTarget(String label, String? currentItem, bool isLeft) {
      final color = const Color(0xFF00AAFF);
      return DragTarget<String>(
        onWillAcceptWithDetails: (d) => canAct && d.data != currentItem,
        onAcceptWithDetails: (d) {
          notifier.equipItem(p.playerId, d.data, toLeft: isLeft);
        },
        builder: (ctx, candidateData, rejectedData) {
          final isDragging = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isDragging
                  ? color.withOpacity(0.3)
                  : color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDragging ? color : color.withOpacity(0.3),
                width: isDragging ? 2 : 0.5,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(isDragging ? Icons.file_download : Icons.back_hand_outlined,
                    color: color, size: 12),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(
                    color: isDragging ? color : const Color(0xFF66BBEE),
                    fontSize: 11, fontFamily: 'monospace',
                    fontWeight: isDragging ? FontWeight.bold : FontWeight.normal)),
              ]),
              const SizedBox(height: 3),
              Text(itemLabel(currentItem),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (itemStats(currentItem).isNotEmpty)
                Text(itemStats(currentItem),
                    style: TextStyle(color: color, fontSize: 12,
                        fontFamily: 'monospace')),
            ]),
          );
        },
      );
    }

    // Backpack draggable slot
    Widget backpackSlot(int i) {
      final itemId = i < p.backpack.length ? p.backpack[i] : null;
      if (itemId == null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF060610),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF111122), width: 0.5),
          ),
          child: const Text('—', style: TextStyle(
              color: Color(0xFF666677), fontSize: 14)),
        );
      }

      return Draggable<String>(
        data: itemId,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFAA00).withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(itemLabel(itemId),
                style: const TextStyle(color: Colors.black,
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        childWhenDragging: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFAA00).withOpacity(0.3),
                width: 1, style: BorderStyle.solid),
          ),
          child: Row(children: [
            Expanded(child: Text(itemLabel(itemId),
                style: const TextStyle(color: Color(0xFF8888AA),
                    fontSize: 12, fontStyle: FontStyle.italic))),
            const Icon(Icons.drag_indicator, color: Color(0xFF666677), size: 14),
          ]),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1A1A2E), width: 0.5),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(itemLabel(itemId),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (itemStats(itemId).isNotEmpty)
                Text(itemStats(itemId),
                    style: const TextStyle(color: Color(0xFF8888AA),
                        fontSize: 12, fontFamily: 'monospace')),
            ])),
            const Icon(Icons.drag_indicator, color: Color(0xFF7777AA), size: 16),
          ]),
        ),
      );
    }

    return Container(
      width: 250,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xF00D0D1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF44BBFF).withOpacity(0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF111122),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Text('INVENTÁRIO', style: TextStyle(
                  color: Color(0xFF44BBFF), fontSize: 12,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222233),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.close, color: Color(0xFFAAAAAA), size: 18),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MÃOS  (arraste itens da mochila até aqui)',
                    style: TextStyle(color: Color(0xFF7777AA), fontSize: 11,
                        fontFamily: 'monospace', letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: handDropTarget('MÃO ESQ', p.equippedLeft, true)),
                  const SizedBox(width: 8),
                  Expanded(child: handDropTarget('MÃO DIR', p.equippedRight, false)),
                ]),
                const SizedBox(height: 12),
                const Text('MOCHILA  (arraste para as mãos — custa 1 ação)',
                    style: TextStyle(color: Color(0xFF7777AA), fontSize: 11,
                        fontFamily: 'monospace', letterSpacing: 0.5)),
                const SizedBox(height: 6),
                ...List.generate(3, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: backpackSlot(i),
                )),
                if (!canAct)
                  const Text('Sem ações restantes para equipar',
                      style: TextStyle(color: Color(0xFFAAAAAA),
                          fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Inventory Panel ----

class _InventoryPanel extends StatelessWidget {
  final PlayerState player;
  final GameBoardGame flameGame;
  final WidgetRef ref;

  const _InventoryPanel({required this.player, required this.flameGame, required this.ref});

  @override
  Widget build(BuildContext context) {
    final notifier  = ref.read(gameSessionProvider.notifier);
    final catalog   = notifier.weaponCatalog;

    WeaponDefinition? weaponOf(String? id) =>
        (id != null && catalog != null) ? catalog.getById(id) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xDD0D0D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333333), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('INVENTÁRIO', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(children: [
            // Left hand
            Expanded(child: _slotCard('MÃO ESQ', player.equippedLeft, weaponOf(player.equippedLeft),
                isActive: flameGame.activeWeaponId == player.equippedLeft,
                onTap: () {
                  if (player.equippedLeft != null) {
                    flameGame.activeWeaponId = player.equippedLeft;
                  }
                })),
            const SizedBox(width: 8),
            // Right hand
            Expanded(child: _slotCard('MÃO DIR', player.equippedRight, weaponOf(player.equippedRight),
                isActive: flameGame.activeWeaponId == player.equippedRight,
                onTap: () {
                  if (player.equippedRight != null) {
                    flameGame.activeWeaponId = player.equippedRight;
                  }
                })),
          ]),
          const SizedBox(height: 8),
          // Backpack
          Row(children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: i < player.backpack.length
                  ? _slotCard('MOCHILA', player.backpack[i], weaponOf(player.backpack[i]))
                  : _emptySlot('MOCHILA')),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _slotCard(String label, String? itemId, WeaponDefinition? def, {bool isActive = false, VoidCallback? onTap}) {
    final color = isActive ? const Color(0xFFFFAA00) : const Color(0xFF00AAFF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1A1400) : const Color(0xFF0A0A16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? const Color(0xFFFFAA00) : const Color(0xFF2A2A3E), width: isActive ? 1 : 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF9999AA), fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 3),
          Text(def?.name ?? itemId ?? '—',
              style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (def != null && def.dice > 0) ...[
            const SizedBox(height: 2),
            Text('${def.dice}d6 / ${def.hitValue}+ / ${def.damage}dmg',
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 10, fontFamily: 'monospace')),
          ],
          if (def != null)
            Row(children: [
              if (def.isNoisy) _tag('BARULHO', const Color(0xFFFF6633)),
              if (def.isMelee) _tag('MELEE',   const Color(0xFF00AAFF)),
              if (def.isRanged) _tag('R:${def.minRange}-${def.maxRange}', const Color(0xFF00FF88)),
            ]),
        ]),
      ),
    );
  }

  Widget _emptySlot(String label) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: const Color(0xFF080810),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFF1A1A2E), width: 0.5),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF9999AA), fontSize: 11, fontFamily: 'monospace')),
      const SizedBox(height: 3),
      const Text('—', style: TextStyle(color: Color(0xFF777788), fontSize: 12, fontFamily: 'monospace')),
    ]),
  );

  Widget _tag(String text, Color color) => Container(
    margin: const EdgeInsets.only(right: 3, top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(2)),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace')),
  );
}

// ---- Loot Choice Panel ----

class _LootChoicePanel extends ConsumerStatefulWidget {
  final String lootId;
  final PlayerState player;

  const _LootChoicePanel({required this.lootId, required this.player});

  @override
  ConsumerState<_LootChoicePanel> createState() => _LootChoicePanelState();
}

class _LootChoicePanelState extends ConsumerState<_LootChoicePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _flip;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _flip    = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.65, curve: Curves.easeOut));
    _slideUp = CurvedAnimation(parent: _ctrl, curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(gameSessionProvider.notifier);
    final catalog  = notifier.weaponCatalog;

    String itemName  = widget.lootId.replaceAll('_', ' ');
    String itemStats = '';
    String itemType  = '';
    bool isMelee = false, isRanged = false, isNoisy = false, isTwoHanded = false;
    try {
      final w = catalog?.getById(widget.lootId);
      if (w != null) {
        itemName    = w.name;
        if (w.dice > 0) itemStats = '${w.dice}d6  ${w.hitValue}+  ${w.damage}dmg';
        isMelee     = w.isMelee;
        isRanged    = w.isRanged;
        isNoisy     = w.isNoisy;
        isTwoHanded = w.hands == 2;
        itemType    = w.isMelee ? 'MELEE' : w.isRanged ? 'RANGED' : 'SUPORTE';
      }
    } catch (_) {}

    final backpackFull = widget.player.backpack.length >= 3;

    String slotLabel(String? id) {
      if (id == null) return 'livre';
      try { return catalog?.getById(id).name ?? id.replaceAll('_', ' '); }
      catch (_) { return id.replaceAll('_', ' '); }
    }

    const accent = Color(0xFFFFAA00);

    Widget slotBtn(String label, String sublabel, bool disabled, String slot, Color color) {
      return Expanded(
        child: GestureDetector(
          onTap: disabled ? null : () => notifier.placeLoot(slot),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: disabled ? const Color(0xFF0A0A14) : color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: disabled ? const Color(0xFF1A1A2E) : color,
                width: disabled ? 0.5 : 1.5,
              ),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(
                color: disabled ? const Color(0xFF777788) : color,
                fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 2),
              Text(sublabel, style: TextStyle(
                color: disabled ? const Color(0xFF888899) : color.withValues(alpha: 0.75),
                fontSize: 11, fontFamily: 'monospace',
              ), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Color(0xFF050510), Color(0xDD050510), Colors.transparent],
        ),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.4), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).padding.bottom + 12),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          // Card flip — back face 0→0.5, front face 0.5→1
          final flipVal    = _flip.value;
          final isFront    = flipVal > 0.5;
          final flipAngle  = isFront ? (flipVal - 1) * math.pi : flipVal * math.pi;
          final slideT     = _slideUp.value;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Loot card (flip animation)
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(flipAngle),
                child: isFront
                    ? _LootCardFront(
                        itemName: itemName,
                        itemStats: itemStats,
                        itemType: itemType,
                        isMelee: isMelee,
                        isRanged: isRanged,
                        isNoisy: isNoisy,
                        isTwoHanded: isTwoHanded,
                        lootId: widget.lootId,
                      )
                    : _LootCardBack(),
              ),

              const SizedBox(width: 12),

              // Slot buttons — slide in after flip
              Expanded(
                child: Opacity(
                  opacity: slideT,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - slideT)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('ONDE GUARDAR?', style: TextStyle(
                          color: Color(0xFFFFAA00), fontSize: 11,
                          fontFamily: 'monospace', fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        )),
                        const SizedBox(height: 8),
                        Row(children: [
                          slotBtn('MÃO ESQ', slotLabel(widget.player.equippedLeft),
                              false, 'left', const Color(0xFF00AAFF)),
                          const SizedBox(width: 6),
                          slotBtn('MÃO DIR', slotLabel(widget.player.equippedRight),
                              false, 'right', const Color(0xFF00AAFF)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          slotBtn('MOCHILA',
                              backpackFull ? 'cheia' : '${widget.player.backpack.length}/3',
                              backpackFull, 'backpack', const Color(0xFFFFAA00)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => notifier.discardLoot(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A0A0A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF666677), width: 0.5),
                              ),
                              child: const Text('DESCARTAR', style: TextStyle(
                                color: Color(0xFFAAAAAA), fontSize: 11,
                                fontFamily: 'monospace',
                              )),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LootCardBack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100, height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF888899), width: 2),
        boxShadow: const [BoxShadow(
            color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: const Center(
        child: Text('?', style: TextStyle(
          fontSize: 40, color: Color(0xFFBBBBCC),
          fontFamily: 'monospace', fontWeight: FontWeight.bold,
        )),
      ),
    );
  }
}

class _LootCardFront extends StatelessWidget {
  final String itemName;
  final String itemStats;
  final String itemType;
  final bool isMelee, isRanged, isNoisy, isTwoHanded;
  final String lootId;

  const _LootCardFront({
    required this.itemName,
    required this.itemStats,
    required this.itemType,
    required this.isMelee,
    required this.isRanged,
    required this.isNoisy,
    required this.isTwoHanded,
    required this.lootId,
  });

  Color get _accentColor {
    if (isNoisy)  return const Color(0xFFFF6633);
    if (isMelee)  return const Color(0xFF0088CC);
    if (isRanged) return const Color(0xFF009944);
    return const Color(0xFF886644);
  }

  @override
  Widget build(BuildContext context) {
    final color = _accentColor;

    return Container(
      width: 100, height: 140,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12, spreadRadius: 1)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Type badge
          if (itemType.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
              ),
              child: Text(itemType, style: TextStyle(
                color: color, fontSize: 10,
                fontFamily: 'monospace', fontWeight: FontWeight.bold,
              )),
            ),

          // Icon
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Center(child: Image.asset(
              'assets/sprites/items/${lootId}.png',
              width: 30, height: 30, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                isMelee  ? Icons.sports_martial_arts
                : isRanged ? Icons.gps_fixed
                : Icons.medical_services,
                color: color, size: 22,
              ),
            )),
          ),

          // Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(itemName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF111122), fontSize: 11,
                fontFamily: 'monospace', fontWeight: FontWeight.bold,
              )),
          ),

          // Stats
          if (itemStats.isNotEmpty)
            Text(itemStats, style: TextStyle(
              color: color, fontSize: 9, fontFamily: 'monospace',
            )),
        ],
      ),
    );
  }
}

// ---- Damage Flash ----

class _DamageFlash extends StatefulWidget {
  final String woundedPlayerId;
  final List<PlayerState> players;
  final VoidCallback onDone;

  const _DamageFlash({
    required this.woundedPlayerId,
    required this.players,
    required this.onDone,
  });

  @override
  State<_DamageFlash> createState() => _DamageFlashState();
}

class _DamageFlashState extends State<_DamageFlash>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    // Quick flash in then fade out
    _opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 80),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward().then((_) => widget.onDone());
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    PlayerState? wounded;
    try {
      wounded = widget.players.firstWhere(
          (p) => p.playerId == widget.woundedPlayerId);
    } catch (_) {}

    final isEliminated = wounded?.isEliminated ?? false;
    final color = isEliminated
        ? const Color(0xFFFF2222)
        : const Color(0xFFFFDD00);
    final label = isEliminated ? 'ELIMINADO' : 'FERIDO';

    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) {
        final a = _opacity.value;
        return IgnorePointer(
          child: Stack(children: [
            // Edge vignette flash
            Positioned.fill(
              child: CustomPaint(painter: _EdgeFlashPainter(color, a)),
            ),
            // Center badge
            Center(
              child: Opacity(
                opacity: a,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: color.withValues(alpha: 0.8), width: 1.5),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(isEliminated ? '💀' : '⚠',
                        style: const TextStyle(fontSize: 32)),
                    const SizedBox(height: 4),
                    Text(label,
                      style: TextStyle(
                        color: color, fontSize: 15,
                        fontFamily: 'monospace', fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      )),
                    if (wounded != null)
                      Text(
                        wounded.definitionId.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.9),
                          fontSize: 13, fontFamily: 'monospace',
                        )),
                  ]),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _EdgeFlashPainter extends CustomPainter {
  final Color color;
  final double opacity;
  _EdgeFlashPainter(this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.2,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.55 * opacity),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_EdgeFlashPainter old) =>
      old.opacity != opacity || old.color != color;
}

// ---- Helpers ----

List<PlayerState> _alliesInSameZone(GameState state, PlayerState active) =>
    state.players.where((p) =>
        !p.isEliminated &&
        p.playerId != active.playerId &&
        p.zoneId == active.zoneId).toList();

// ---- Trade Panel ----

class _TradePanel extends StatefulWidget {
  final GameState gameState;
  final WidgetRef ref;
  final VoidCallback onClose;

  const _TradePanel({required this.gameState, required this.ref, required this.onClose});

  @override
  State<_TradePanel> createState() => _TradePanelState();
}

class _TradePanelState extends State<_TradePanel> {
  String? _selectedItem;
  String? _targetPlayerId;

  @override
  Widget build(BuildContext context) {
    final game   = widget.gameState;
    final active = game.players.firstWhere((p) => p.playerId == game.activePlayerId);
    final allies = _alliesInSameZone(game, active);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xDD0D0D1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF44DDAA).withOpacity(0.4), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('TROCAR ITEM', style: TextStyle(
                color: Color(0xFF44DDAA), fontSize: 10,
                fontFamily: 'monospace', letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, color: Color(0xFF555555), size: 16),
            ),
          ]),
          const SizedBox(height: 8),
          // Step 1: pick item
          const Text('1. Selecione o item:', style: TextStyle(
              color: Color(0xFF888888), fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: active.allItems.map((item) {
              final isSelected = _selectedItem == item;
              return GestureDetector(
                onTap: () => setState(() => _selectedItem = isSelected ? null : item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF44DDAA).withOpacity(0.2)
                        : const Color(0xFF0A0A14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF44DDAA)
                          : const Color(0xFF222233),
                      width: 0.5,
                    ),
                  ),
                  child: Text(item.replaceAll('_', ' '),
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF44DDAA) : const Color(0xFF888888),
                        fontSize: 11, fontFamily: 'monospace',
                      )),
                ),
              );
            }).toList(),
          ),
          if (active.allItems.isEmpty)
            const Text('Inventário vazio.', style: TextStyle(
                color: Color(0xFF444466), fontSize: 11)),
          const SizedBox(height: 10),
          // Step 2: pick target
          const Text('2. Dar para:', style: TextStyle(
              color: Color(0xFF888888), fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: allies.map((ally) {
              final isSelected = _targetPlayerId == ally.playerId;
              final name = ally.definitionId.split('_').last.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() =>
                    _targetPlayerId = isSelected ? null : ally.playerId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF44DDAA).withOpacity(0.2)
                        : const Color(0xFF0A0A14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF44DDAA)
                          : const Color(0xFF222233),
                      width: 0.5,
                    ),
                  ),
                  child: Text(name, style: TextStyle(
                    color: isSelected ? const Color(0xFF44DDAA) : const Color(0xFF888888),
                    fontSize: 11, fontFamily: 'monospace',
                  )),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _canConfirm
                    ? const Color(0xFF44DDAA)
                    : const Color(0xFF111111),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: _canConfirm ? _confirm : null,
              child: const Text('CONFIRMAR TROCA',
                  style: TextStyle(fontFamily: 'monospace',
                      fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canConfirm => _selectedItem != null && _targetPlayerId != null;

  void _confirm() {
    widget.ref.read(gameSessionProvider.notifier).tradeItem(
      widget.gameState.activePlayerId,
      _targetPlayerId!,
      _selectedItem!,
    );
    widget.onClose();
  }
}
