import '../core/models/campaign.dart';
import '../core/models/mission.dart';
import 'asset_loader.dart';

const _indexPath = 'assets/data/campaigns/index.json';

class CampaignRepository {
  final AssetLoader _loader;

  // In-memory cache — loaded once per app session.
  final Map<String, CampaignDefinition> _campaigns = {};
  final Map<String, MissionDefinition> _missions = {};
  bool _loaded = false;

  CampaignRepository(this._loader);

  Future<void> load() async {
    if (_loaded) return;

    final index = await _loader.loadJson(_indexPath);
    final entries = index['campaigns'] as List;

    for (final entry in entries) {
      final manifestPath = entry['manifestPath'] as String;
      final missionPaths = (entry['missionPaths'] as List).cast<String>();

      final manifest = await _loader.loadJson(manifestPath);
      final campaign = CampaignDefinition.fromJson(manifest);
      _campaigns[campaign.id] = campaign;

      for (final path in missionPaths) {
        final missionJson = await _loader.loadJson(path);
        final mission = MissionDefinition.fromJson(missionJson);
        _missions[mission.id] = mission;
      }
    }

    _loaded = true;
  }

  List<CampaignDefinition> getAllCampaigns() {
    _assertLoaded();
    return _campaigns.values.toList();
  }

  CampaignDefinition getCampaignById(String id) {
    _assertLoaded();
    final c = _campaigns[id];
    if (c == null) throw ArgumentError('Unknown campaign id: $id');
    return c;
  }

  List<MissionDefinition> getMissionsForCampaign(String campaignId) {
    _assertLoaded();
    final campaign = getCampaignById(campaignId);
    return campaign.missionIds
        .map((id) => _missions[id])
        .whereType<MissionDefinition>()
        .toList();
  }

  MissionDefinition getMissionById(String id) {
    _assertLoaded();
    final m = _missions[id];
    if (m == null) throw ArgumentError('Unknown mission id: $id');
    return m;
  }

  /// Returns only missions the player can currently play,
  /// given the set of already completed mission IDs.
  List<MissionDefinition> getAvailableMissions(
    String campaignId,
    Set<String> completedMissionIds,
  ) {
    return getMissionsForCampaign(campaignId).where((mission) {
      return mission.requiredCompletedMissions
          .every(completedMissionIds.contains);
    }).toList();
  }

  void _assertLoaded() {
    if (!_loaded) {
      throw StateError(
        'CampaignRepository not loaded. Call load() before use.',
      );
    }
  }
}
