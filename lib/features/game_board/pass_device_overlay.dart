import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/player.dart';
import '../../data/providers.dart';

class PassDeviceOverlay extends ConsumerWidget {
  final PlayerState player;
  final VoidCallback onReady;

  const PassDeviceOverlay({
    super.key,
    required this.player,
    required this.onReady,
  });

  static Color _roleColor(PlayerRole? role) => switch (role) {
    PlayerRole.scout    => const Color(0xFF00BBFF),
    PlayerRole.engineer => const Color(0xFFFFB800),
    PlayerRole.medic    => const Color(0xFF00FF88),
    PlayerRole.soldier  => const Color(0xFFFF5533),
    null                => const Color(0xFF888888),
  };

  static String _roleLabel(PlayerRole? role) => switch (role) {
    PlayerRole.scout    => 'INFILTRADOR',
    PlayerRole.engineer => 'ENGENHEIRO',
    PlayerRole.medic    => 'MÉDICO',
    PlayerRole.soldier  => 'SOLDADO',
    null                => 'OPERADOR',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definition = ref
        .watch(playerCatalogProvider)
        .valueOrNull
        ?.getById(player.definitionId);

    final color     = _roleColor(definition?.role);
    final name      = definition?.name ?? player.definitionId;
    final roleLabel = _roleLabel(definition?.role);

    return Material(
      color: const Color(0xF2050510),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PASSE O DISPOSITIVO',
                    style: TextStyle(
                      color: Color(0xFF555566),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A),
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                          border:
                              Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            color: color,
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 0.18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'VEZ DE',
                        style: TextStyle(
                          color: Color(0xFF555566),
                          fontFamily: 'monospace',
                          fontSize: 12,
                          letterSpacing: 0.14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontFamily: 'monospace',
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.02,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${player.actionsRemaining} ações  ·  ${player.health} HP',
                        style: const TextStyle(
                          color: Color(0xFF444455),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: onReady,
                    child: const Text(
                      'ESTOU PRONTO',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.1,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Não mostre esta tela aos outros jogadores',
                  style: TextStyle(
                    color: Color(0xFF2A2A3A),
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
