import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/enemy_turn_script.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/game_state.dart';
import 'game_board_game.dart';
import 'board_hud.dart';
import 'enemy_cinematic_overlay.dart';

class GameBoardScreen extends ConsumerStatefulWidget {
  const GameBoardScreen({super.key});

  @override
  ConsumerState<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends ConsumerState<GameBoardScreen> {
  GameBoardGame?        _game;
  GameState?            _pendingSync;
  EnemyTurnScript?      _activeCinematic;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  void _initGame() {
    final session  = ref.read(gameSessionProvider);
    if (session == null) return;
    final notifier = ref.read(gameSessionProvider.notifier);

    final game = GameBoardGame(
      gameState:           session.game,
      mission:             session.mission,
      onMoveToZone:        (pid, zoneId, wx, wy) => notifier.movePlayer(pid, wx, wy),
      onAttackZone:        (pid, wid, cx, cy) => notifier.attackZone(pid, wid, cx, cy),
      onSearch:            (pid, objId) => notifier.search(pid, objId),
      onInteract:          (pid, objId) => notifier.interact(pid, objId),
      onOpenDoor:          (pid, from, to) => notifier.openDoor(pid, from, to),
      onActionModeChanged: (_) {},
    );

    game.loaded.then((_) {
      if (_pendingSync != null) {
        game.syncState(_pendingSync!);
        _pendingSync = null;
      }
    });

    setState(() => _game = game);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(gameSessionProvider);

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Trigger cinematic when a new script arrives.
    ref.listen(enemyCinematicProvider, (prev, next) {
      if (next != null && !next.isEmpty && _activeCinematic == null) {
        // Wait one frame so the board syncs enemy positions first.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _activeCinematic = next);
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final g = _game;
      if (g == null) return;
      if (g.isLoaded) {
        g.syncState(session.game);
      } else {
        _pendingSync = session.game;
      }
    });

    ref.listen(gameOutcomeProvider, (_, outcome) {
      if (outcome != GameOutcome.none && context.mounted) context.go('/result');
    });

    return Scaffold(
      body: Stack(
        children: [
          if (_game != null) GameWidget(game: _game!),
          if (_game != null) SafeArea(child: BoardHud(game: _game!)),

          // Enemy phase cinematic — covers HUD, board stays visible underneath.
          if (_activeCinematic != null && _game != null)
            SafeArea(
              child: EnemyCinematicOverlay(
                script: _activeCinematic!,
                game:   _game!,
                onComplete: () {
                  setState(() => _activeCinematic = null);
                  // Pan to the active player now that it's their turn.
                  final s = ref.read(gameSessionProvider);
                  final g = _game;
                  if (s != null && g != null && g.isLoaded) {
                    try {
                      final p = s.game.players.firstWhere(
                        (p) => p.playerId == s.game.activePlayerId && !p.isEliminated,
                      );
                      g.animateCameraTo(p.x.toDouble(), p.y.toDouble(), ms: 500);
                    } catch (_) {}
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
