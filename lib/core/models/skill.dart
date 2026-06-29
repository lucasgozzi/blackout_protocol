import 'player.dart';

enum SkillEffectType {
  extraMovement,    // +N tiles to movement range
  extraDice,        // +N dice on attack
  ignoreArmor,      // bypass enemy armor
  extraAction,      // +1 action per turn
  freeOpenDoor,     // open door costs no action
  healOnSearch,     // restore 1 danger level when searching
  areaAttack,       // attack hits all zones in range, not just one
  rangedBonus,      // +N range to ranged weapons
}

class SkillEffect {
  final SkillEffectType type;
  final int value; // magnitude (e.g. +1, +2)
  const SkillEffect({required this.type, this.value = 1});
}

class SkillDefinition {
  final String id;
  final String name;
  final String description;
  final DangerLevel unlocksAt;
  final SkillEffect effect;

  const SkillDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.unlocksAt,
    required this.effect,
  });
}

// ---- Skill catalog — hardcoded per survivor ----

const Map<String, List<SkillDefinition>> kSurvivorSkills = {
  'scout_aria': [
    SkillDefinition(
      id: 'aria_fast_move',
      name: 'Movimento Ágil',
      description: '+1 zona de movimento por turno.',
      unlocksAt: DangerLevel.blue,
      effect: SkillEffect(type: SkillEffectType.extraMovement, value: 1),
    ),
    SkillDefinition(
      id: 'aria_quick_shot',
      name: 'Tiro Rápido',
      description: '+1 dado em ataques à distância.',
      unlocksAt: DangerLevel.yellow,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 1),
    ),
    SkillDefinition(
      id: 'aria_extended_range',
      name: 'Alcance Estendido',
      description: '+1 de alcance em armas de fogo.',
      unlocksAt: DangerLevel.orange,
      effect: SkillEffect(type: SkillEffectType.rangedBonus, value: 1),
    ),
    SkillDefinition(
      id: 'aria_sprint',
      name: 'Velocidade Máxima',
      description: '+2 ações por turno.',
      unlocksAt: DangerLevel.red,
      effect: SkillEffect(type: SkillEffectType.extraAction, value: 2),
    ),
  ],
  'engineer_rex': [
    SkillDefinition(
      id: 'rex_free_door',
      name: 'Acesso Técnico',
      description: 'Abrir portas não gasta ação.',
      unlocksAt: DangerLevel.blue,
      effect: SkillEffect(type: SkillEffectType.freeOpenDoor),
    ),
    SkillDefinition(
      id: 'rex_hack',
      name: 'Hack Avançado',
      description: '+2 dados ao buscar em salas de servidores.',
      unlocksAt: DangerLevel.yellow,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 2),
    ),
    SkillDefinition(
      id: 'rex_armor_pierce',
      name: 'Penetração EMP',
      description: 'Ignora armadura de drones e robôs.',
      unlocksAt: DangerLevel.orange,
      effect: SkillEffect(type: SkillEffectType.ignoreArmor),
    ),
    SkillDefinition(
      id: 'rex_overcharge',
      name: 'Sobrecarga',
      description: '+1 ação extra por turno.',
      unlocksAt: DangerLevel.red,
      effect: SkillEffect(type: SkillEffectType.extraAction, value: 1),
    ),
  ],
  'medic_nova': [
    SkillDefinition(
      id: 'nova_triage',
      name: 'Triagem',
      description: 'Ao buscar, recupera 1 nível de perigo.',
      unlocksAt: DangerLevel.blue,
      effect: SkillEffect(type: SkillEffectType.healOnSearch),
    ),
    SkillDefinition(
      id: 'nova_steady_hands',
      name: 'Mãos Firmes',
      description: '+1 dado em ataques de melee.',
      unlocksAt: DangerLevel.yellow,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 1),
    ),
    SkillDefinition(
      id: 'nova_adrenaline',
      name: 'Adrenalina',
      description: '+1 ação por turno.',
      unlocksAt: DangerLevel.orange,
      effect: SkillEffect(type: SkillEffectType.extraAction, value: 1),
    ),
    SkillDefinition(
      id: 'nova_area_heal',
      name: 'Pulso de Cura',
      description: '+2 dados em todos os ataques.',
      unlocksAt: DangerLevel.red,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 2),
    ),
  ],
  'soldier_kai': [
    SkillDefinition(
      id: 'kai_heavy_hitter',
      name: 'Força Bruta',
      description: '+1 dado em ataques corpo a corpo.',
      unlocksAt: DangerLevel.blue,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 1),
    ),
    SkillDefinition(
      id: 'kai_suppression',
      name: 'Supressão',
      description: '+1 dado em ataques à distância.',
      unlocksAt: DangerLevel.yellow,
      effect: SkillEffect(type: SkillEffectType.extraDice, value: 1),
    ),
    SkillDefinition(
      id: 'kai_armor_break',
      name: 'Quebra-Armadura',
      description: 'Ignora toda armadura inimiga.',
      unlocksAt: DangerLevel.orange,
      effect: SkillEffect(type: SkillEffectType.ignoreArmor),
    ),
    SkillDefinition(
      id: 'kai_berserker',
      name: 'Berserker',
      description: '+2 ações por turno.',
      unlocksAt: DangerLevel.red,
      effect: SkillEffect(type: SkillEffectType.extraAction, value: 2),
    ),
  ],
};

/// Returns all skills unlocked for a player given their current danger level.
List<SkillDefinition> unlockedSkillsFor(String definitionId, DangerLevel level) {
  final all = kSurvivorSkills[definitionId] ?? [];
  return all.where((s) => s.unlocksAt.index <= level.index).toList();
}

/// Returns only newly unlocked skills when transitioning levels.
List<SkillDefinition> newlyUnlockedSkills(
    String definitionId, DangerLevel previous, DangerLevel current) {
  if (current.index <= previous.index) return [];
  final all = kSurvivorSkills[definitionId] ?? [];
  return all.where((s) =>
      s.unlocksAt.index > previous.index &&
      s.unlocksAt.index <= current.index).toList();
}
