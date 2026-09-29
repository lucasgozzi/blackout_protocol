import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/engine/game_session_notifier.dart';
import '../../core/models/player.dart';
import '../../core/models/skill.dart';
import '../../core/rules/skill_system.dart';

class SurvivorDashboard extends ConsumerWidget {
  final String playerId;
  final VoidCallback onClose;

  const SurvivorDashboard({
    super.key,
    required this.playerId,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final player = session.game.players.firstWhere(
      (p) => p.playerId == playerId,
      orElse: () => session.game.players.first,
    );

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // absorb taps inside
            child: Container(
              width: 340,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _dangerColor(player).withOpacity(0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Header(player: player, onClose: onClose),
                  _XpTrack(player: player),
                  _SkillSlots(player: player),
                  _InventorySlots(player: player, ref: ref),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _dangerColor(PlayerState p) => switch (p.dangerLevel) {
    DangerLevel.blue   => const Color(0xFF00FF88),
    DangerLevel.yellow => const Color(0xFFFFDD00),
    DangerLevel.orange => const Color(0xFFFF8800),
    DangerLevel.red    => const Color(0xFFFF2222),
  };
}

// ---- Header ----

class _Header extends StatelessWidget {
  final PlayerState player;
  final VoidCallback onClose;

  const _Header({required this.player, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final color = SurvivorDashboard._dangerColor(player);
    final name  = player.definitionId.split('_').last.toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: color.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          // Portrait or icon
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.asset(
                'assets/sprites/characters/${player.definitionId}_portrait.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: color.withOpacity(0.1),
                  child: Icon(Icons.person, color: color, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold,
                  fontFamily: 'monospace', letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(
                  '${player.dangerLevel.name.toUpperCase()}  ·  '
                  'XP ${player.xp}  ·  '
                  '${player.actionsRemaining} ações',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF555555), size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ---- XP Track ----

class _XpTrack extends StatelessWidget {
  final PlayerState player;
  const _XpTrack({required this.player});

  static const _levels = [
    (label: 'BLUE',   xp: 0,  color: Color(0xFF00FF88)),
    (label: 'YELLOW', xp: 7,  color: Color(0xFFFFDD00)),
    (label: 'ORANGE', xp: 19, color: Color(0xFFFF8800)),
    (label: 'RED',    xp: 43, color: Color(0xFFFF2222)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TRILHA DE XP', style: TextStyle(
              color: Color(0xFF444466), fontSize: 10,
              fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: _levels.map((lvl) {
              final isActive  = player.xp >= lvl.xp;
              final isCurrent = _currentLevel(player.xp) == lvl.label;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? lvl.color.withOpacity(isCurrent ? 0.25 : 0.1)
                        : const Color(0xFF0A0A14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive ? lvl.color : const Color(0xFF1A1A2E),
                      width: isCurrent ? 1.5 : 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(lvl.label,
                          style: TextStyle(
                            color: isActive ? lvl.color : const Color(0xFF333344),
                            fontSize: 8, fontFamily: 'monospace',
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          )),
                      if (lvl.xp > 0)
                        Text('${lvl.xp}+',
                            style: TextStyle(
                              color: isActive
                                  ? lvl.color.withOpacity(0.6)
                                  : const Color(0xFF222233),
                              fontSize: 7, fontFamily: 'monospace',
                            )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          // XP bar
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _xpFraction(player.xp),
              backgroundColor: const Color(0xFF1A1A2E),
              color: SurvivorDashboard._dangerColor(player),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 3),
          Text('${player.xp} XP  ·  próximo nível: ${_nextThreshold(player.xp)} XP',
              style: const TextStyle(color: Color(0xFF555566),
                  fontSize: 9, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  static String _currentLevel(int xp) {
    if (xp >= 43) return 'RED';
    if (xp >= 19) return 'ORANGE';
    if (xp >= 7)  return 'YELLOW';
    return 'BLUE';
  }

  static double _xpFraction(int xp) {
    if (xp >= 43) return 1.0;
    if (xp >= 19) return (xp - 19) / (43 - 19);
    if (xp >= 7)  return (xp - 7) / (19 - 7);
    return xp / 7.0;
  }

  static int _nextThreshold(int xp) {
    if (xp < 7)  return 7;
    if (xp < 19) return 19;
    if (xp < 43) return 43;
    return 43;
  }
}

// ---- Skill Slots ----

class _SkillSlots extends StatelessWidget {
  final PlayerState player;
  const _SkillSlots({required this.player});

  static const _dangerOrder = [
    DangerLevel.blue, DangerLevel.yellow, DangerLevel.orange, DangerLevel.red,
  ];

  @override
  Widget build(BuildContext context) {
    final allSkills = kSurvivorSkills[player.definitionId] ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HABILIDADES', style: TextStyle(
              color: Color(0xFF444466), fontSize: 10,
              fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 8),
          ...allSkills.map((skill) {
            final unlocked = player.dangerLevel.index >= skill.unlocksAt.index;
            final levelColor = _levelColor(skill.unlocksAt);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: unlocked
                    ? levelColor.withOpacity(0.08)
                    : const Color(0xFF080810),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: unlocked ? levelColor.withOpacity(0.4) : const Color(0xFF1A1A2E),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: unlocked
                          ? levelColor.withOpacity(0.15)
                          : const Color(0xFF0A0A14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      _skillIcon(skill.effect.type),
                      color: unlocked ? levelColor : const Color(0xFF2A2A3E),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(skill.name,
                              style: TextStyle(
                                color: unlocked ? Colors.white : const Color(0xFF333344),
                                fontSize: 12, fontWeight: FontWeight.bold,
                              )),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: levelColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(skill.unlocksAt.name.toUpperCase(),
                                style: TextStyle(color: levelColor, fontSize: 7,
                                    fontFamily: 'monospace')),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(skill.description,
                            style: TextStyle(
                              color: unlocked
                                  ? const Color(0xFF888888)
                                  : const Color(0xFF2A2A3E),
                              fontSize: 11,
                            )),
                      ],
                    ),
                  ),
                  if (!unlocked)
                    const Icon(Icons.lock_outline, color: Color(0xFF2A2A3E), size: 16),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static Color _levelColor(DangerLevel l) => switch (l) {
    DangerLevel.blue   => const Color(0xFF00FF88),
    DangerLevel.yellow => const Color(0xFFFFDD00),
    DangerLevel.orange => const Color(0xFFFF8800),
    DangerLevel.red    => const Color(0xFFFF2222),
  };

  static IconData _skillIcon(SkillEffectType t) => switch (t) {
    SkillEffectType.extraMovement => Icons.directions_run,
    SkillEffectType.extraDice     => Icons.casino_outlined,
    SkillEffectType.ignoreArmor   => Icons.shield_outlined,
    SkillEffectType.extraAction   => Icons.bolt,
    SkillEffectType.freeOpenDoor  => Icons.door_front_door_outlined,
    SkillEffectType.healOnSearch  => Icons.medical_services_outlined,
    SkillEffectType.healAlly         => Icons.favorite_border,
    SkillEffectType.areaHealAlly     => Icons.favorite,
    SkillEffectType.damageResistance => Icons.security,
    SkillEffectType.electricTrap     => Icons.electric_bolt,
    SkillEffectType.areaAttack       => Icons.radar,
    SkillEffectType.rangedBonus      => Icons.gps_fixed,
  };
}

// ---- Inventory Slots ----

class _InventorySlots extends StatelessWidget {
  final PlayerState player;
  final WidgetRef ref;

  const _InventorySlots({required this.player, required this.ref});

  @override
  Widget build(BuildContext context) {
    final catalog = ref.read(gameSessionProvider.notifier).weaponCatalog;

    String itemName(String? id) {
      if (id == null) return '';
      try {
        return catalog?.getById(id).name ?? id;
      } catch (_) {
        return id.replaceAll('_', ' ');
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('INVENTÁRIO', style: TextStyle(
              color: Color(0xFF444466), fontSize: 10,
              fontFamily: 'monospace', letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _slot('MÃO ESQ', player.equippedLeft, itemName(player.equippedLeft),
                const Color(0xFF00AAFF))),
            const SizedBox(width: 8),
            Expanded(child: _slot('MÃO DIR', player.equippedRight, itemName(player.equippedRight),
                const Color(0xFF00AAFF))),
          ]),
          const SizedBox(height: 6),
          Row(children: List.generate(3, (i) {
            final item = i < player.backpack.length ? player.backpack[i] : null;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                child: _slot('MOCHILA', item, itemName(item), const Color(0xFF888888)),
              ),
            );
          })),
        ],
      ),
    );
  }

  Widget _slot(String label, String? itemId, String name, Color color) {
    final isEmpty = itemId == null;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isEmpty ? const Color(0xFF080810) : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEmpty ? const Color(0xFF1A1A2E) : color.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF333355),
              fontSize: 8, fontFamily: 'monospace')),
          const SizedBox(height: 3),
          Text(
            isEmpty ? '—' : name,
            style: TextStyle(
              color: isEmpty ? const Color(0xFF222233) : Colors.white,
              fontSize: 11, fontWeight: FontWeight.bold,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
