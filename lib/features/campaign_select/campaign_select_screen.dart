import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/campaign.dart';
import '../../data/providers.dart';

class CampaignSelectScreen extends ConsumerWidget {
  const CampaignSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(allCampaignsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        title: const Text(
          'CAMPANHAS',
          style: TextStyle(color: Color(0xFF00FF88), fontFamily: 'monospace', letterSpacing: 3),
        ),
      ),
      body: campaignsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
        error: (e, _) => Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
        data: (campaigns) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: campaigns.length,
          itemBuilder: (_, i) => _CampaignCard(campaign: campaigns[i]),
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final CampaignDefinition campaign;

  const _CampaignCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final isFree = campaign.access == CampaignAccess.free;

    return GestureDetector(
      onTap: () => context.push('/campaigns/${campaign.id}/missions'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A2E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      campaign.title.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF00FF88),
                        fontFamily: 'monospace',
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isFree
                          ? const Color(0xFF00FF88).withOpacity(0.15)
                          : const Color(0xFFFFAA00).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isFree ? const Color(0xFF00FF88) : const Color(0xFFFFAA00),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      isFree ? 'GRÁTIS' : 'PREMIUM',
                      style: TextStyle(
                        color: isFree ? const Color(0xFF00FF88) : const Color(0xFFFFAA00),
                        fontSize: 10,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.description,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _stat(Icons.map_outlined, '${campaign.missionCount} missões'),
                      const SizedBox(width: 16),
                      _stat(Icons.arrow_forward_ios, 'Jogar'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF00AAFF)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFF00AAFF), fontSize: 12, fontFamily: 'monospace')),
      ],
    );
  }
}
