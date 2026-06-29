import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/game_state.dart';

class GamePlaceholderScreen extends ConsumerWidget {
  const GamePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameSessionProvider);

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Navigate to result when game ends.
    ref.listen(gameOutcomeProvider, (_, outcome) {
      if (outcome != GameOutcome.none && context.mounted) {
        context.go('/result');
      }
    });

    final game = session.game;

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        automaticallyImplyLeading: false,
        title: Text(
          session.mission.title.toUpperCase(),
          style: const TextStyle(color: Color(0xFF00FF88), fontFamily: 'monospace', letterSpacing: 2, fontSize: 14),
        ),
        actions: [
          // Alert level indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Color(0xFFFF4444), size: 16),
                const SizedBox(width: 4),
                Text(
                  '${game.alertLevel}/${session.mission.maxAlertLevel}',
                  style: const TextStyle(color: Color(0xFFFF4444), fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRoundBar(game),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('OPERADORES', game.players.map((p) =>
                    '${p.definitionId.split("_").last.toUpperCase()}  '
                    'xp:${p.xp}  ações:${p.actionsRemaining}  '
                    '${p.dangerLevel.name.toUpperCase()}'
                    '${p.isEliminated ? "  ✗ ELIMINADO" : ""}'
                  ).toList()),
                  _section('AMEAÇAS (${game.enemies.length})', game.enemies.isEmpty
                    ? ['Área limpa']
                    : game.enemies.map((e) =>
                        '${e.definitionId}  hp:${e.currentHp}  (${e.x},${e.y})'
                      ).toList()),
                  _section('OBJETIVOS', game.objectives.map((o) =>
                    '${o.isCompleted ? "✓" : "○"}  ${o.description}'
                  ).toList()),
                  _section('LOG', game.eventLog.reversed.take(6).toList()),
                ],
              ),
            ),
          ),
          _buildActionBar(ref, game),
        ],
      ),
    );
  }

  Widget _buildRoundBar(GameState game) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0D0D1A),
      child: Row(
        children: [
          _pill('ROUND ${game.round}', const Color(0xFF00AAFF)),
          const SizedBox(width: 8),
          _pill(game.phase.name.toUpperCase(), const Color(0xFF00FF88)),
          const Spacer(),
          _pill('ALERTA ${game.alertLevel}', game.alertLevel >= 7
              ? const Color(0xFFFF4444)
              : game.alertLevel >= 4
                  ? const Color(0xFFFFAA00)
                  : const Color(0xFF555555)),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontFamily: 'monospace', letterSpacing: 0.5)),
    );
  }

  Widget _section(String title, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Color(0xFF555555), fontSize: 11, letterSpacing: 1, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A16),
            border: Border.all(color: const Color(0xFF1A1A2E)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, fontFamily: 'monospace')),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(WidgetRef ref, GameState game) {
    final notifier = ref.read(gameSessionProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FF88),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: game.outcome == GameOutcome.none
              ? () => notifier.endPlayerTurn()
              : null,
          child: const Text(
            'ENCERRAR TURNO',
            style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
      ),
    );
  }
}
