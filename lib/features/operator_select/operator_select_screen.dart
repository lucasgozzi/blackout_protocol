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
  ConsumerState<OperatorSelectScreen> createState() =>
      _OperatorSelectScreenState();
}

class _OperatorSelectScreenState extends ConsumerState<OperatorSelectScreen> {
  final Set<String> _selected = {};
  late final PageController _pageCtrl;
  int _currentPage = 0;

  static const int _minOperators = 1;
  static const int _maxOperators = 4;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.88);
    _pageCtrl.addListener(() {
      final p = _pageCtrl.page?.round() ?? 0;
      if (p != _currentPage) setState(() => _currentPage = p);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(missionByIdProvider(widget.missionId));
    final playerCatalogAsync = ref.watch(playerCatalogProvider);

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
          style: TextStyle(
            color: Color(0xFF00FF88),
            fontFamily: 'monospace',
            letterSpacing: 3,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_selected.length}/$_maxOperators',
                style: TextStyle(
                  color: _selected.isNotEmpty
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF444455),
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
      body: missionAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
        error: (e, _) =>
            Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
        data: (mission) => playerCatalogAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
          error: (e, _) =>
              Center(child: Text('Erro: $e', style: const TextStyle(color: Colors.red))),
          data: (playerCatalog) {
            final available = mission.availablePlayers
                .map((id) => playerCatalog.getById(id))
                .toList();

            return Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: available.length,
                    itemBuilder: (_, i) {
                      final player = available[i];
                      final isSelected = _selected.contains(player.id);
                      return _OperatorPage(
                        player: player,
                        isSelected: isSelected,
                        isFocused: i == _currentPage,
                        onToggle: () => _toggleOperator(player.id),
                        canSelect: _selected.length < _maxOperators || isSelected,
                      );
                    },
                  ),
                ),
                _BottomBar(
                  selected: _selected,
                  available: available,
                  canLaunch: _selected.length >= _minOperators,
                  onLaunch: () => _launch(mission, playerCatalog),
                  onAvatarTap: (id) {
                    final idx = available.indexWhere((p) => p.id == id);
                    if (idx >= 0) {
                      _pageCtrl.animateToPage(
                        idx,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _launch(mission, playerCatalog) async {
    final enemyCatalog = await ref.read(enemyCatalogProvider.future);
    final selectedPlayers = _selected
        .map<PlayerDefinition>((id) => playerCatalog.getById(id))
        .toList();

    final mapId = mission.mapAsset
        .split('/')
        .last
        .replaceAll('.tmj', '')
        .replaceAll('.json', '');
    List<String> startZoneIds = [];
    List<String> spawnZones = [];
    try {
      final mapData = await MapLoader(FlutterAssetLoader()).load(mapId);
      startZoneIds = mapData.playerStartPositions.map((s) => s.zoneId).toList();
      spawnZones = mapData.globalSpawnZoneIds.toList();
    } catch (_) {}

    final notifier = ref.read(gameSessionProvider.notifier);
    notifier.init(enemyCatalog);
    notifier.startMission(mission, selectedPlayers,
        startZoneIds: startZoneIds, spawnZones: spawnZones);

    if (mounted) context.go('/game');
  }
}

// ─── Carousel page ────────────────────────────────────────────────────────────

class _OperatorPage extends StatelessWidget {
  final PlayerDefinition player;
  final bool isSelected;
  final bool isFocused;
  final bool canSelect;
  final VoidCallback onToggle;

  const _OperatorPage({
    required this.player,
    required this.isSelected,
    required this.isFocused,
    required this.canSelect,
    required this.onToggle,
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

  static const _weaponLabels = {
    'pistol':  'Pistola',
    'shotgun': 'Escopeta',
    'crowbar': 'Pé-de-cabra',
    'rifle':   'Rifle',
    'smg':     'SMG',
  };

  @override
  Widget build(BuildContext context) {
    final color  = _roleColors[player.role] ?? Colors.white;
    final skills = kSurvivorSkills[player.id] ?? [];

    return AnimatedScale(
      scale: isFocused ? 1.0 : 0.93,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.15),
              width: isSelected ? 1.5 : 0.75,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: 2)]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final portraitHeight = constraints.maxHeight * 0.52;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: portraitHeight,
                      child: _buildPortrait(color),
                    ),
                    Expanded(child: _buildDetails(context, color, skills)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortrait(Color color) {
    return Stack(
      children: [
        // Portrait image
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Image.asset(
            'assets/sprites/characters/${player.id}_portrait.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: color.withValues(alpha: 0.06),
              child: Icon(Icons.person_outline,
                  color: color.withValues(alpha: 0.25), size: 64),
            ),
          ),
        ),
        // Gradient overlay so text below doesn't clash
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  const Color(0xFF0D0D1A).withValues(alpha: 0.6),
                  const Color(0xFF0D0D1A),
                ],
                stops: const [0.0, 0.5, 0.82, 1.0],
              ),
            ),
          ),
        ),
        // Selected checkmark
        if (isSelected)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.black, size: 16),
            ),
          ),
        // Role badge overlay at bottom of portrait
        Positioned(
          bottom: 8,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
            ),
            child: Text(
              _roleLabels[player.role] ?? player.role.name.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'monospace',
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Weapon badge
        Positioned(
          bottom: 8,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF333355), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gps_fixed, color: Color(0xFF555577), size: 10),
                const SizedBox(width: 4),
                Text(
                  _weaponLabels[player.startingWeapon] ??
                      player.startingWeapon.replaceAll('_', ' '),
                  style: const TextStyle(
                    color: Color(0xFF777799),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, Color color, List<SkillDefinition> skills) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          Text(
            player.name.toUpperCase(),
            style: TextStyle(
              color: isSelected ? color : Colors.white,
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          // Description
          Text(
            player.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF666677),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // Skill tree
          ...DangerLevel.values.map((level) {
            final skill = skills.where((s) => s.unlocksAt == level).firstOrNull;
            final lvlColor = _levelColors[level]!;
            final isBlue = level == DangerLevel.blue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: lvlColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
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
                  SizedBox(
                    width: 36,
                    child: Text(
                      _levelXp[level]!,
                      style: const TextStyle(
                        color: Color(0xFF444455),
                        fontSize: 8,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
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
                  GestureDetector(
                    onTap: skill != null
                        ? () => _showSkillDetail(context, skill, lvlColor)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.info_outline,
                        size: 12,
                        color: skill != null
                            ? lvlColor.withValues(alpha: 0.5)
                            : const Color(0xFF222233),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Spacer(),
          // Select / Deselect button
          SizedBox(
            width: double.infinity,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? color.withValues(alpha: 0.15)
                      : (canSelect ? color : const Color(0xFF1A1A2E)),
                  foregroundColor: isSelected
                      ? color
                      : (canSelect ? Colors.black : const Color(0xFF444455)),
                  side: BorderSide(
                    color: isSelected ? color : Colors.transparent,
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  elevation: 0,
                ),
                onPressed: (canSelect || isSelected) ? onToggle : null,
                child: Text(
                  isSelected ? 'REMOVER DO TIME' : 'ADICIONAR AO TIME',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSkillDetail(BuildContext context, SkillDefinition skill, Color color) {
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
                skill.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                skill.description,
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
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
}

// ─── Bottom bar ───────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final Set<String> selected;
  final List<PlayerDefinition> available;
  final bool canLaunch;
  final VoidCallback onLaunch;
  final void Function(String id) onAvatarTap;

  const _BottomBar({
    required this.selected,
    required this.available,
    required this.canLaunch,
    required this.onLaunch,
    required this.onAvatarTap,
  });

  static const _roleColors = {
    PlayerRole.scout:    Color(0xFF00FF88),
    PlayerRole.engineer: Color(0xFF00AAFF),
    PlayerRole.medic:    Color(0xFFFF6688),
    PlayerRole.soldier:  Color(0xFFFFAA00),
  };

  @override
  Widget build(BuildContext context) {
    final selectedPlayers = available.where((p) => selected.contains(p.id)).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
      ),
      child: Row(
        children: [
          // Mini avatars of selected operators
          ...List.generate(4, (i) {
            final player = i < selectedPlayers.length ? selectedPlayers[i] : null;
            final color = player != null
                ? (_roleColors[player.role] ?? Colors.white)
                : const Color(0xFF1A1A2E);
            return GestureDetector(
              onTap: player != null ? () => onAvatarTap(player.id) : null,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: player != null ? color : const Color(0xFF2A2A3E),
                    width: player != null ? 1.5 : 1,
                  ),
                  color: player != null
                      ? color.withValues(alpha: 0.1)
                      : const Color(0xFF0D0D1A),
                ),
                child: player != null
                    ? ClipOval(
                        child: Image.asset(
                          'assets/sprites/characters/${player.id}_portrait.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person,
                            color: color.withValues(alpha: 0.7),
                            size: 18,
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Color(0xFF333344),
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            );
          }),
          const Spacer(),
          // Launch button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  canLaunch ? const Color(0xFF00FF88) : const Color(0xFF1A1A2E),
              foregroundColor:
                  canLaunch ? Colors.black : const Color(0xFF444444),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            icon: const Icon(Icons.rocket_launch, size: 16),
            label: const Text(
              'INICIAR',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontSize: 12,
              ),
            ),
            onPressed: canLaunch ? onLaunch : null,
          ),
        ],
      ),
    );
  }
}
