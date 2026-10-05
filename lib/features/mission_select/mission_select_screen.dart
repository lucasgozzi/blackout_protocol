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
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontSize: 14,
            ),
          ),
        ),
      ),
      body: _MissionList(campaignId: campaignId),
    );
  }
}

class _MissionList extends ConsumerWidget {
  final String campaignId;
  const _MissionList({required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(missionsForCampaignProvider(campaignId));
    final completedAsync = ref.watch(completedMissionsProvider);

    return missionsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00FF88)),
      ),
      error: (e, _) => Center(
        child: Text('Erro: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (missions) {
        final completed = completedAsync.value ?? {};
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: missions.length,
          itemBuilder: (_, i) {
            final mission = missions[i];
            final isUnlocked = mission.requiredCompletedMissions.every(
              completed.contains,
            );
            return _MissionCard(
              mission: mission,
              index: i,
              isUnlocked: isUnlocked,
              isCompleted: completed.contains(mission.id),
              onTap: () => context.push(
                '/campaigns/$campaignId/missions/${mission.id}/operators',
              ),
            );
          },
        );
      },
    );
  }
}

class _MissionCard extends StatelessWidget {
  final MissionDefinition mission;
  final int index;
  final bool isUnlocked;
  final bool isCompleted;
  final VoidCallback onTap;

  const _MissionCard({
    required this.mission,
    required this.index,
    required this.isUnlocked,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isCompleted
        ? const Color(0xFF00FF88)
        : isUnlocked
            ? const Color(0xFF00AAFF)
            : const Color(0xFF333333);

    return GestureDetector(
      onTap: isUnlocked ? onTap : null,
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.4,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            border: Border.all(color: borderColor.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Mission number / completed badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF00FF88).withValues(alpha: 0.15)
                        : isUnlocked
                            ? const Color(0xFF00AAFF).withValues(alpha: 0.15)
                            : const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check,
                            size: 18,
                            color: Color(0xFF00FF88),
                          )
                        : Text(
                            '${index + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                              color: isUnlocked
                                  ? const Color(0xFF00AAFF)
                                  : const Color(0xFF444444),
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
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _tag(
                            Icons.flag_outlined,
                            'Alert máx: ${mission.maxAlertLevel}',
                          ),
                          const SizedBox(width: 12),
                          if (mission.maxRounds > 0)
                            _tag(
                              Icons.timer_outlined,
                              '${mission.maxRounds} rounds',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Lock / arrow / check
                Icon(
                  isCompleted
                      ? Icons.check_circle_outline
                      : isUnlocked
                          ? Icons.chevron_right
                          : Icons.lock_outline,
                  color: isCompleted
                      ? const Color(0xFF00FF88)
                      : isUnlocked
                          ? const Color(0xFF00AAFF)
                          : const Color(0xFF333333),
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
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF555555),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
