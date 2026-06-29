import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/player.dart';
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
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: available.length,
                    itemBuilder: (_, i) => _OperatorCard(
                      player: available[i],
                      isSelected: _selected.contains(available[i].id),
                      onTap: () => _toggleOperator(available[i].id),
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
          Text(
            'Selecione ${_minOperators}–$_maxOperators operadores',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
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
    List<({int x, int y})> startPositions = [];
    Map<String, String> spawnZoneCoords = {};
    try {
      final mapData = await MapLoader(FlutterAssetLoader()).load(mapId);
      startPositions = List.generate(4, (i) {
        final pos = mapData.playerStartWorldPos(i);
        return (x: pos.x.toInt(), y: pos.y.toInt());
      });
      // Build spawn zone coordinate map for the spawn system.
      for (final zoneId in mapData.globalSpawnZoneIds) {
        final found = mapData.findZone(zoneId);
        if (found != null) {
          final c = mapData.zoneCenter(found.tile, found.zone);
          spawnZoneCoords[zoneId] = '${c.x.toInt()},${c.y.toInt()}';
        }
      }
    } catch (_) {}

    final notifier = ref.read(gameSessionProvider.notifier);
    notifier.init(enemyCatalog);
    notifier.startMission(mission, selectedPlayers,
        startPositions: startPositions,
        spawnZoneCoords: spawnZoneCoords);

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
    PlayerRole.scout: Color(0xFF00FF88),
    PlayerRole.engineer: Color(0xFF00AAFF),
    PlayerRole.medic: Color(0xFFFF6688),
    PlayerRole.soldier: Color(0xFFFFAA00),
  };

  static const _roleLabels = {
    PlayerRole.scout: 'BATEDOR',
    PlayerRole.engineer: 'ENGENHEIRO',
    PlayerRole.medic: 'MÉDICO',
    PlayerRole.soldier: 'SOLDADO',
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[player.role] ?? Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : const Color(0xFF0D0D1A),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF333333),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Role badge + checkmark
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _roleLabels[player.role] ?? player.role.name.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace', letterSpacing: 0.5),
                    ),
                  ),
                  const Spacer(),
                  if (isSelected)
                    Icon(Icons.check_circle, color: color, size: 18),
                ],
              ),
              const Spacer(),
              // Portrait
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? color : color.withOpacity(0.3),
                      width: isSelected ? 1.5 : 0.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.asset(
                      'assets/sprites/characters/${player.id}_portrait.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: color.withOpacity(0.08),
                        child: Icon(Icons.person_outline,
                            color: color.withOpacity(0.6), size: 32),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Name
              Text(
                player.name.toUpperCase(),
                style: TextStyle(
                  color: isSelected ? color : Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                player.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF666666), fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 8),
              // Abilities
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: player.startingAbilities.map((a) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    a.replaceAll('_', ' '),
                    style: const TextStyle(color: Color(0xFF555555), fontSize: 10, fontFamily: 'monospace'),
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
