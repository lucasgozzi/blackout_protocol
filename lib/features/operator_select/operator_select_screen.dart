import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/player.dart';
import '../../core/models/skill.dart';
import '../../data/providers.dart';
import '../../data/map_loader.dart';
import '../../data/asset_loader.dart';

class OperatorSelectScreen extends ConsumerStatefulWidget {
  final String campaignId;
  final String missionId;

  const OperatorSelectScreen({
    super.key,
    required this.campaignId,
    required this.missionId,
  });

  @override
  ConsumerState<OperatorSelectScreen> createState() => _OperatorSelectScreenState();
}

class _OperatorSelectScreenState extends ConsumerState<OperatorSelectScreen> {
  final Set<String> _selected = {};
  static const int _minOperators = 1;
  static const int _maxOperators = 4;

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(missionByIdProvider(widget.missionId));
    final playerCatalogAsync = ref.watch(playerCatalogProvider);
    final enemyCatalogAsync = ref.watch(enemyCatalogProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00FF88)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'OPERADORES',
          style: TextStyle(color: Color(0xFF00FF88), fontFamily: 'monospace', letterSpacing: 3),
        ),
      ),
      body: missionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
        error: (e, _) => Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
        data: (mission) => playerCatalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
          error: (e, _) => Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
          data: (playerCatalog) {
            final available = mission.availablePlayers
                .map((id) => playerCatalog.getById(id))
                .toList();

            return Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: available.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OperatorCard(
                        player: available[i],
                        isSelected: _selected.contains(available[i].id),
                        onTap: () => _toggleOperator(available[i].id),
                      ),
                    ),
                  ),
                ),
                _buildLaunchButton(mission, playerCatalog, enemyCatalogAsync),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0D0D1A),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, color: Color(0xFF00AAFF), size: 16),
          const SizedBox(width: 8),
          const Text(
            'Selecione 1–4 operadores',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13),
          ),
          const Spacer(),
          Text(
            '${_selected.length}/$_maxOperators',
            style: TextStyle(
              color: _selected.isNotEmpty ? const Color(0xFF00FF88) : const Color(0xFF555555),
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchButton(mission, playerCatalog, enemyCatalogAsync) {
    final canLaunch = _selected.length >= _minOperators;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: canLaunch ? const Color(0xFF00FF88) : const Color(0xFF1A1A2E),
            foregroundColor: canLaunch ? Colors.black : const Color(0xFF444444),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          icon: const Icon(Icons.rocket_launch, size: 18),
          label: const Text(
            'INICIAR MISSÃO',
            style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          onPressed: canLaunch
              ? () => _launch(mission, playerCatalog, enemyCatalogAsync)
              : null,
        ),
      ),
    );
  }

  void _toggleOperator(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _maxOperators) {
        _selected.add(id);
      }
    });
  }

  Future<void> _launch(mission, playerCatalog, enemyCatalogAsync) async {
    final enemyCatalog = await ref.read(enemyCatalogProvider.future);
    final selectedPlayers = _selected.map<PlayerDefinition>((id) => playerCatalog.getById(id)).toList();

    // Load map to get player start positions.
    final mapId = mission.mapAsset
        .split('/').last
        .replaceAll('.tmj', '').replaceAll('.json', '');
    List<String> startZoneIds = [];
    List<String> spawnZones   = [];
    try {
      final mapData = await MapLoader(FlutterAssetLoader()).load(mapId);
      startZoneIds = mapData.playerStartPositions.map((s) => s.zoneId).toList();
      spawnZones   = mapData.globalSpawnZoneIds.toList();
    } catch (_) {}

    final notifier = ref.read(gameSessionProvider.notifier);
    notifier.init(enemyCatalog);
    notifier.startMission(mission, selectedPlayers,
        startZoneIds: startZoneIds,
        spawnZones:   spawnZones);

    if (mounted) context.go('/game');
  }
}

class _OperatorCard extends StatelessWidget {
  final PlayerDefinition player;
  final bool isSelected;
  final VoidCallback onTap;

  const _OperatorCard({
    required this.player,
    required this.isSelected,
    required this.onTap,
  });

  static const _roleColors = {
    PlayerRole.scout:    Color(0xFF00FF88),
    PlayerRole.engineer: Color(0xFF00AAFF),
    PlayerRole.medic:    Color(0xFFFF6688),
    PlayerRole.soldier:  Color(0xFFFFAA00),
  };

  static const _roleLabels = {
    PlayerRole.scout:    'BATEDOR',
    PlayerRole.engineer: 'ENGENHEIRO',
    PlayerRole.medic:    'MÉDICO',
    PlayerRole.soldier:  'SOLDADO',
  };

  static const _levelColors = {
    DangerLevel.blue:   Color(0xFF4488FF),
    DangerLevel.yellow: Color(0xFFFFCC00),
    DangerLevel.orange: Color(0xFFFF8800),
    DangerLevel.red:    Color(0xFFFF3333),
  };

  static const _levelLabels = {
    DangerLevel.blue:   'AZUL',
    DangerLevel.yellow: 'AMARELO',
    DangerLevel.orange: 'LARANJA',
    DangerLevel.red:    'VERMELHO',
  };

  static const _levelXp = {
    DangerLevel.blue:   'Início',
    DangerLevel.yellow: '7 XP',
    DangerLevel.orange: '19 XP',
    DangerLevel.red:    '43 XP',
  };

  void _showAllSkills(BuildContext context, List<SkillDefinition> skills, Color color) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D0D1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HABILIDADES',
                style: TextStyle(
                  color: color,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              ...DangerLevel.values.map((level) {
                final skill = skills.where((s) => s.unlocksAt == level).firstOrNull;
                final lvlColor = _levelColors[level]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(color: lvlColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              skill?.name.toUpperCase() ?? '—',
                              style: TextStyle(
                                color: skill != null ? Colors.white70 : const Color(0xFF444455),
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (skill != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                skill.description,
                                style: TextStyle(
                                  color: lvlColor.withValues(alpha: 0.6),
                                  fontSize: 11,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    'FECHAR',
                    style: TextStyle(
                      color: color,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1,
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

  static String _weaponLabel(String id) {
    const names = {
      'pistol':   'Pistola',
      'shotgun':  'Escopeta',
      'crowbar':  'Pé-de-cabra',
      'rifle':    'Rifle',
      'smg':      'SMG',
    };
    return names[id] ?? id.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final color  = _roleColors[player.role] ?? Colors.white;
    final skills = kSurvivorSkills[player.id] ?? [];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : const Color(0xFF0D0D1A),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF2A2A3E),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Portrait column
              Column(
                children: [
                  Container(
                    width: 72,
                    height: 88,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? color : color.withValues(alpha: 0.25),
                        width: isSelected ? 1.5 : 0.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'assets/sprites/characters/${player.id}_portrait.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: color.withValues(alpha: 0.06),
                          child: Icon(Icons.person_outline,
                              color: color.withValues(alpha: 0.5), size: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Starting weapon badge
                  Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF333355), width: 0.5),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.gps_fixed, color: Color(0xFF555577), size: 14),
                        const SizedBox(height: 2),
                        Text(
                          _weaponLabel(player.startingWeapon),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF777799),
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role badge + hint + checkmark
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _roleLabels[player.role] ?? player.role.name.toUpperCase(),
                            style: TextStyle(
                              color: color, fontSize: 9,
                              fontFamily: 'monospace', letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showAllSkills(context, skills, color),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color.withValues(alpha: 0.35),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '?',
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.55),
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle, color: color, size: 18),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Name
                    Text(
                      player.name.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? color : Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF555566), fontSize: 10, height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Skill tree
                    ...DangerLevel.values.map((level) {
                      final skill = skills.where((s) => s.unlocksAt == level).firstOrNull;
                      final lvlColor = _levelColors[level]!;
                      final isBlue = level == DangerLevel.blue;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            // Level dot
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: lvlColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Level label
                            SizedBox(
                              width: 52,
                              child: Text(
                                _levelLabels[level]!,
                                style: TextStyle(
                                  color: lvlColor.withValues(alpha: 0.7),
                                  fontSize: 8,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            // XP threshold
                            SizedBox(
                              width: 32,
                              child: Text(
                                _levelXp[level]!,
                                style: const TextStyle(
                                  color: Color(0xFF444455),
                                  fontSize: 8,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            // Skill name
                            Expanded(
                              child: Text(
                                skill?.name ?? '—',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: skill != null
                                      ? (isBlue ? Colors.white70 : Colors.white54)
                                      : const Color(0xFF333344),
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: isBlue ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
