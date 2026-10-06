import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/enemy_turn_script.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/game_state.dart';
import '../../core/models/player.dart';
import '../../core/models/skill.dart';
import '../../data/providers.dart';
import 'game_board_game.dart';
import 'board_hud.dart';
import 'enemy_cinematic_overlay.dart';
import 'level_up_overlay.dart';
import 'pass_device_overlay.dart';
import 'tutorial_hint_overlay.dart';

class GameBoardScreen extends ConsumerStatefulWidget {
  const GameBoardScreen({super.key});

  @override
  ConsumerState<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends ConsumerState<GameBoardScreen> {
  GameBoardGame?        _game;
  GameState?            _pendingSync;
  EnemyTurnScript?      _activeCinematic;
  LevelUpEvent?         _levelUpEvent;
  // Tracks last-known danger levels to detect transitions.
  final Map<String, DangerLevel> _knownLevels = {};

  // Pass & Play: tracks the last active player to detect turn transitions.
  String?      _lastActivePlayerId;
  PlayerState? _pendingPassDevice; // queued until cinematic finishes
  PlayerState? _passDevicePlayer;  // currently showing the hand-off modal

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  void _initGame() {
    final session  = ref.read(gameSessionProvider);
    if (session == null) return;
    // Seed so the first turn never triggers the hand-off modal.
    _lastActivePlayerId = session.game.activePlayerId;
    final notifier = ref.read(gameSessionProvider.notifier);

    final game = GameBoardGame(
      gameState:           session.game,
      mission:             session.mission,
      onMoveToZone:        (pid, zoneId) => notifier.movePlayer(pid, zoneId),
      onAttackZone:        (pid, wid, zoneId) => notifier.attackZone(pid, wid, zoneId),
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

    // Detect level-up transitions and pass-device hand-offs.
    ref.listen(gameSessionProvider, (prev, next) {
      if (prev == null || next == null) return;

      // Level-up detection.
      for (final player in next.game.players) {
        final prevLevel = _knownLevels[player.playerId];
        final currLevel = player.dangerLevel;
        if (prevLevel != null && prevLevel != currLevel) {
          final unlocked = newlyUnlockedSkills(
            player.definitionId, prevLevel, currLevel);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _levelUpEvent = LevelUpEvent(
                playerName:     player.definitionId,
                newLevel:       currLevel,
                unlockedSkills: unlocked,
              ));
            }
          });
        }
        _knownLevels[player.playerId] = currLevel;
      }

      // Pass & Play: show hand-off modal when the active player changes.
      // Suppressed in networked multiplayer (each device = one player).
      final mpInfo = ref.read(multiplayerInfoProvider);
      final currId = next.game.activePlayerId;
      final aliveCount =
          next.game.players.where((p) => !p.isEliminated).length;

      if (mpInfo == null && // solo / pass & play only
          aliveCount > 1 &&
          currId != _lastActivePlayerId &&
          next.game.phase == GamePhase.playerTurn) {
        PlayerState? incoming;
        for (final p in next.game.players) {
          if (p.playerId == currId && !p.isEliminated) {
            incoming = p;
            break;
          }
        }
        if (incoming != null) {
          // If a cinematic is about to play (or already running), defer
          // the modal until onComplete so it doesn't interrupt the animation.
          final hasCinematic = next.cinematicScript != null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (hasCinematic || _activeCinematic != null) {
              setState(() => _pendingPassDevice = incoming);
            } else {
              setState(() => _passDevicePlayer = incoming);
            }
          });
        }
      }
      _lastActivePlayerId = currId;
    });

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

    final pendingHint  = ref.watch(pendingHintProvider);
    final mpInfo       = ref.watch(multiplayerInfoProvider);
    final activePlayer = ref.watch(activePlayerProvider);
    final isMyTurn = mpInfo == null ||
        session.game.activePlayerId == mpInfo.myPlayerId;

    return Scaffold(
      body: Stack(
        children: [
          if (_game != null) GameWidget(game: _game!),
          if (_game != null) SafeArea(child: BoardHud(game: _game!)),

          // Multiplayer: "waiting for X" banner when it's not this device's turn.
          if (mpInfo != null && !isMyTurn && _activeCinematic == null)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A).withValues(alpha: 0.92),
                    border: Border.all(color: const Color(0xFF333344)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFF00AAFF)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Turno de ${activePlayer?.definitionId ?? '...'}',
                        style: const TextStyle(
                          color: Color(0xFF00AAFF),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Tutorial hint modal — shown above HUD, below cinematic.
          if (pendingHint != null && _activeCinematic == null)
            TutorialHintOverlay(hint: pendingHint),

          // Level-up notification banner.
          if (_levelUpEvent != null)
            LevelUpOverlay(
              event: _levelUpEvent!,
              onDismiss: () => setState(() => _levelUpEvent = null),
            ),

          // Enemy phase cinematic — covers HUD, board stays visible underneath.
          if (_activeCinematic != null && _game != null)
            SafeArea(
              child: EnemyCinematicOverlay(
                script: _activeCinematic!,
                game:   _game!,
                onComplete: () {
                  setState(() {
                    _activeCinematic = null;
                    // Flush any queued pass-device modal now that the
                    // cinematic is done.
                    if (_pendingPassDevice != null) {
                      _passDevicePlayer = _pendingPassDevice;
                      _pendingPassDevice = null;
                    }
                  });
                  // Pan to the active player now that it's their turn.
                  final s = ref.read(gameSessionProvider);
                  final g = _game;
                  if (s != null && g != null && g.isLoaded) {
                    try {
                      final p = s.game.players.firstWhere(
                        (p) => p.playerId == s.game.activePlayerId && !p.isEliminated,
                      );
                      final pos = g.worldPosForZone(p.zoneId);
                      g.animateCameraTo(pos.x, pos.y, ms: 500);
                    } catch (_) {}
                  }
                },
              ),
            ),

          // Pass & Play hand-off — shown above everything after each turn.
          if (_passDevicePlayer != null)
            PassDeviceOverlay(
              player:  _passDevicePlayer!,
              onReady: () => setState(() => _passDevicePlayer = null),
            ),
        ],
      ),
    );
  }
}
