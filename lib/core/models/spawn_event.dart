import 'enemy.dart';

class SpawnEvent {
  final String zoneId;
  final String zoneName;
  final String enemyId;
  final String enemyName;
  final int count;
  final EnemyTier tier;

  const SpawnEvent({
    required this.zoneId,
    required this.zoneName,
    required this.enemyId,
    required this.enemyName,
    required this.count,
    required this.tier,
  });
}
