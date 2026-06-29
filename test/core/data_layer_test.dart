import 'package:flutter_test/flutter_test.dart';
import 'package:blackout_protocol/data/asset_loader.dart';
import 'package:blackout_protocol/data/enemy_catalog.dart';
import 'package:blackout_protocol/data/campaign_repository.dart';
import 'package:blackout_protocol/core/models/enemy.dart';
import 'package:blackout_protocol/core/models/mission.dart';
import 'package:blackout_protocol/core/models/campaign.dart';

// FileAssetLoader reads from the filesystem root of the project.
// Tests must be run from the project root: `flutter test`
final _loader = FileAssetLoader('.');

void main() {
  group('EnemyCatalog', () {
    late EnemyCatalog catalog;

    setUpAll(() async {
      catalog = await EnemyCatalog.load(_loader);
    });

    test('loads all enemies from JSON', () {
      expect(catalog.getAll(), isNotEmpty);
    });

    test('getById returns correct definition', () {
      final drone = catalog.getById('drone_walker');
      expect(drone.name, 'Corrupted Scout Drone');
      expect(drone.type, EnemyType.corruptedDrone);
      expect(drone.tier, EnemyTier.walker);
      expect(drone.hp, 1);
      expect(drone.actions, 1);
    });

    test('SENTINEL-9 has correct stats', () {
      final sentinel = catalog.getById('security_abomination');
      expect(sentinel.tier, EnemyTier.abomination);
      expect(sentinel.hp, 10);
      expect(sentinel.damage, 3);
      expect(sentinel.specialAbilities, containsAll(['armor_2', 'ranged_attack', 'area_damage']));
    });

    test('getByType returns only matching type', () {
      final drones = catalog.getByType(EnemyType.corruptedDrone);
      expect(drones.every((e) => e.type == EnemyType.corruptedDrone), isTrue);
    });

    test('getById throws on unknown id', () {
      expect(() => catalog.getById('nonexistent'), throwsArgumentError);
    });
  });

  group('CampaignRepository', () {
    late CampaignRepository repo;

    setUpAll(() async {
      repo = CampaignRepository(_loader);
      await repo.load();
    });

    test('loads campaign_01', () {
      final campaigns = repo.getAllCampaigns();
      expect(campaigns, hasLength(1));
      expect(campaigns.first.id, 'campaign_01');
    });

    test('campaign_01 has correct metadata', () {
      final c = repo.getCampaignById('campaign_01');
      expect(c.title, 'Blackout Protocol');
      expect(c.access, CampaignAccess.free);
      expect(c.missionCount, 3);
      expect(c.missionIds, hasLength(3));
    });

    test('loads all 3 missions for campaign_01', () {
      final missions = repo.getMissionsForCampaign('campaign_01');
      expect(missions, hasLength(3));
    });

    // ---- Mission 1 ----

    test('mission 1 has correct structure', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      expect(m.campaignId, 'campaign_01');
      expect(m.missionNumber, 1);
      expect(m.maxAlertLevel, 10);
      expect(m.maxRounds, 12);
    });

    test('mission 1 has 2 primary objectives and 1 bonus', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      final primary = m.objectives.where((o) => o.isPrimary).toList();
      final bonus = m.objectives.where((o) => !o.isPrimary).toList();
      expect(primary, hasLength(2));
      expect(bonus, hasLength(1));
    });

    test('mission 1 has 3 spawn points', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      expect(m.spawnPoints, hasLength(3));
      expect(m.spawnPoints.map((s) => s.id), containsAll(['sp_north', 'sp_east', 'sp_south']));
    });

    test('mission 1 spawn rules reference valid enemy ids', () async {
      final catalog = await EnemyCatalog.load(_loader);
      final m = repo.getMissionById('c01_m01_fuel_depot');
      for (final rule in m.spawnRules) {
        expect(
          () => catalog.getById(rule.enemyId),
          returnsNormally,
          reason: 'spawn rule references unknown enemy: ${rule.enemyId}',
        );
      }
    });

    test('mission 1 spawn rules reference valid spawn point ids', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      final spawnIds = m.spawnPoints.map((s) => s.id).toSet();
      for (final rule in m.spawnRules) {
        expect(
          spawnIds.contains(rule.spawnPointId),
          isTrue,
          reason: 'spawn rule references unknown spawn point: ${rule.spawnPointId}',
        );
      }
    });

    test('mission 1 alert events have valid trigger levels', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      for (final event in m.alertEvents) {
        expect(event.triggerAlertLevel, inInclusiveRange(1, m.maxAlertLevel));
      }
    });

    test('mission 1 starting items are non-empty', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      expect(m.startingItems, isNotEmpty);
    });

    // ---- Mission ordering and unlock chain ----

    test('mission 1 has no prerequisites', () {
      final m = repo.getMissionById('c01_m01_fuel_depot');
      expect(m.requiredCompletedMissions, isEmpty);
    });

    test('mission 2 requires mission 1', () {
      final m = repo.getMissionById('c01_m02_rescue_scientist');
      expect(m.requiredCompletedMissions, contains('c01_m01_fuel_depot'));
    });

    test('mission 3 requires mission 2', () {
      final m = repo.getMissionById('c01_m03_disable_antenna');
      expect(m.requiredCompletedMissions, contains('c01_m02_rescue_scientist'));
    });

    test('getAvailableMissions returns only mission 1 when nothing completed', () {
      final available = repo.getAvailableMissions('campaign_01', {});
      expect(available, hasLength(1));
      expect(available.first.id, 'c01_m01_fuel_depot');
    });

    test('getAvailableMissions unlocks mission 2 after completing mission 1', () {
      final available = repo.getAvailableMissions(
        'campaign_01',
        {'c01_m01_fuel_depot'},
      );
      expect(available.map((m) => m.id), contains('c01_m02_rescue_scientist'));
    });

    test('getAvailableMissions unlocks all missions when chain complete', () {
      final available = repo.getAvailableMissions(
        'campaign_01',
        {'c01_m01_fuel_depot', 'c01_m02_rescue_scientist'},
      );
      expect(available, hasLength(3));
    });

    test('getCampaignById throws on unknown id', () {
      expect(() => repo.getCampaignById('nonexistent'), throwsArgumentError);
    });

    test('getMissionById throws on unknown id', () {
      expect(() => repo.getMissionById('nonexistent'), throwsArgumentError);
    });

    test('load() is idempotent — calling twice does not duplicate data', () async {
      await repo.load();
      expect(repo.getAllCampaigns(), hasLength(1));
    });

    // ---- Cross-mission consistency ----

    test('all missions reference valid enemy ids in spawn rules', () async {
      final catalog = await EnemyCatalog.load(_loader);
      final missions = repo.getMissionsForCampaign('campaign_01');
      for (final mission in missions) {
        for (final rule in mission.spawnRules) {
          expect(
            () => catalog.getById(rule.enemyId),
            returnsNormally,
            reason: '${mission.id}: unknown enemy ${rule.enemyId}',
          );
        }
      }
    });

    test('all missions have at least one primary objective', () {
      final missions = repo.getMissionsForCampaign('campaign_01');
      for (final m in missions) {
        expect(
          m.objectives.any((o) => o.isPrimary),
          isTrue,
          reason: '${m.id} has no primary objective',
        );
      }
    });

    test('all missions have at least one spawn point', () {
      final missions = repo.getMissionsForCampaign('campaign_01');
      for (final m in missions) {
        expect(m.spawnPoints, isNotEmpty, reason: '${m.id} has no spawn points');
      }
    });
  });
}
