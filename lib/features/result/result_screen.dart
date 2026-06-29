import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/game_state.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameSessionProvider);
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/campaigns'));
      return const SizedBox.shrink();
    }

    final game = session.game;
    final isVictory = game.outcome == GameOutcome.victory;

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Outcome icon
              Icon(
                isVictory ? Icons.shield_outlined : Icons.dangerous_outlined,
                size: 72,
                color: isVictory ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
              ),
              const SizedBox(height: 24),
              Text(
                isVictory ? 'MISSÃO CONCLUÍDA' : 'MISSÃO FALHOU',
                style: TextStyle(
                  color: isVictory ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
                  fontSize: 22,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                session.mission.title,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 14, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 40),
              // Stats
              _statsCard(game),
              const SizedBox(height: 40),
              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isVictory ? const Color(0xFF00FF88) : const Color(0xFF00AAFF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {
                    ref.read(gameSessionProvider.notifier).endSession();
                    context.go('/campaigns');
                  },
                  child: Text(
                    isVictory ? 'PRÓXIMA MISSÃO' : 'TENTAR NOVAMENTE',
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  ref.read(gameSessionProvider.notifier).endSession();
                  context.go('/campaigns');
                },
                child: const Text(
                  'VOLTAR AO MENU',
                  style: TextStyle(color: Color(0xFF555555), fontFamily: 'monospace', letterSpacing: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCard(GameState game) {
    final survivors = game.players.where((p) => !p.isEliminated).length;
    final totalXp = game.players.fold(0, (sum, p) => sum + p.xp);
    final objectivesDone = game.objectives.where((o) => o.isCompleted && o.isPrimary).length;
    final totalObjectives = game.objectives.where((o) => o.isPrimary).length;
    final bonusDone = game.objectives.where((o) => o.isCompleted && !o.isPrimary).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border.all(color: const Color(0xFF1A1A2E)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _statRow('Rounds', '${game.round}'),
          _statRow('Alert final', '${game.alertLevel}'),
          _statRow('Sobreviventes', '$survivors/${game.players.length}'),
          _statRow('XP total', '$totalXp'),
          _statRow('Objetivos', '$objectivesDone/$totalObjectives'),
          if (bonusDone > 0) _statRow('Bônus', '$bonusDone'),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF888888), fontFamily: 'monospace', fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
