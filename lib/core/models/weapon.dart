enum WeaponType { melee, ranged, support, armor }

class WeaponDefinition {
  final String id;
  final String name;
  final WeaponType type;
  final int minRange;
  final int maxRange;
  final int dice;
  final int hitValue; // roll >= hitValue on d6 = hit
  final int damage;
  final int hands;   // 0 = passive (armor), 1 = one-handed, 2 = two-handed
  final bool isNoisy;
  final bool isConsumable;
  // Only fire/explosive weapons can damage an Abomination.
  final bool canHurtAbomination;

  const WeaponDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.minRange,
    required this.maxRange,
    required this.dice,
    required this.hitValue,
    required this.damage,
    required this.hands,
    required this.isNoisy,
    required this.isConsumable,
    this.canHurtAbomination = false,
  });

  bool get isMelee  => type == WeaponType.melee;
  bool get isRanged => type == WeaponType.ranged;

  bool canTargetRange(int distance) =>
      distance >= minRange && distance <= maxRange;

  factory WeaponDefinition.fromJson(Map<String, dynamic> j) => WeaponDefinition(
    id:           j['id']           as String,
    name:         j['name']         as String,
    type:         _parseType(j['type'] as String),
    minRange:     j['minRange']     as int,
    maxRange:     j['maxRange']     as int,
    dice:         j['dice']         as int,
    hitValue:     j['hitValue']     as int,
    damage:       j['damage']       as int,
    hands:        j['hands']        as int,
    isNoisy:             j['isNoisy']             as bool,
    isConsumable:        j['isConsumable']        as bool,
    canHurtAbomination:  j['canHurtAbomination']  as bool? ?? false,
  );

  static WeaponType _parseType(String s) => switch (s) {
    'melee'   => WeaponType.melee,
    'ranged'  => WeaponType.ranged,
    'support' => WeaponType.support,
    'armor'   => WeaponType.armor,
    _         => WeaponType.melee,
  };

  // Fallback bare-hands weapon.
  static const fists = WeaponDefinition(
    id: 'fists', name: 'Punhos', type: WeaponType.melee,
    minRange: 0, maxRange: 0, dice: 1, hitValue: 5, damage: 1,
    hands: 1, isNoisy: false, isConsumable: false, canHurtAbomination: false,
  );
}
