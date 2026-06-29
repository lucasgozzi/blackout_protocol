import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/mission.dart';
import '../../data/providers.dart';

class MissionSelectScreen extends ConsumerWidget {
  final String campaignId;

  const MissionSelectScreen({super.key, required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignAsync = ref.watch(campaignByIdProvider(campaignId));
    final missionsAsync = ref.watch(missionsForCampaignProvider(campaignId));

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00FF88)),
          onPressed: () => context.pop(),
        ),
        title: campaignAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (c) => Text(
            c.title.toUpperCase(),
            style: const TextStyle(color: Color(0xFF00FF88), fontFamily: 'monospace', letterSpacing: 2, fontSize: 14),
          ),
        ),
      ),
      body: missionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
        error: (e, _) => Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
        data: (missions) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: missions.length,
          itemBuilder: (_, i) => _MissionCard(
            mission: missions[i],
            index: i,
            // For now, mission 1 is always unlocked; rest require previous.
            isUnlocked: i == 0 || missions[i].requiredCompletedMissions.isEmpty,
            onTap: () => context.push(
              '/campaigns/$campaignId/missions/${missions[i].id}/operators',
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final MissionDefinition mission;
  final int index;
  final bool isUnlocked;
  final VoidCallback onTap;

  const _MissionCard({
    required this.mission,
    required this.index,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUnlocked ? onTap : null,
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.4,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            border: Border.all(
              color: isUnlocked
                  ? const Color(0xFF00AAFF).withOpacity(0.4)
                  : const Color(0xFF333333),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Mission number
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isUnlocked
                        ? const Color(0xFF00AAFF).withOpacity(0.15)
                        : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isUnlocked ? const Color(0xFF00AAFF) : const Color(0xFF333333),
                      width: 0.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: isUnlocked ? const Color(0xFF00AAFF) : const Color(0xFF444444),
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mission.title.toUpperCase(),
                        style: TextStyle(
                          color: isUnlocked ? Colors.white : const Color(0xFF555555),
                          fontFamily: 'monospace',
                          fontSize: 13,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mission.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF666666), fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _tag(Icons.flag_outlined, 'Alert máx: ${mission.maxAlertLevel}'),
                          const SizedBox(width: 12),
                          if (mission.maxRounds > 0)
                            _tag(Icons.timer_outlined, '${mission.maxRounds} rounds'),
                        ],
                      ),
                    ],
                  ),
                ),
                // Lock / arrow
                Icon(
                  isUnlocked ? Icons.chevron_right : Icons.lock_outline,
                  color: isUnlocked ? const Color(0xFF00AAFF) : const Color(0xFF333333),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 11, color: const Color(0xFF555555)),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(color: Color(0xFF555555), fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}
