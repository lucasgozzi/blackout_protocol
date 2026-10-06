import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/campaign.dart';
import '../core/models/mission.dart';
import '../core/models/enemy.dart';
import '../core/models/player.dart';
import 'asset_loader.dart';
import 'campaign_repository.dart';
import 'enemy_catalog.dart';
import 'identity_service.dart';
import 'multiplayer_info.dart';
import 'player_catalog.dart';
import 'progress_repository.dart';
import 'room_service.dart';

// ---- Infrastructure ----

final assetLoaderProvider = Provider<AssetLoader>((_) => FlutterAssetLoader());

// ---- Data repositories ----

final enemyCatalogProvider = FutureProvider<EnemyCatalog>((ref) {
  final loader = ref.read(assetLoaderProvider);
  return EnemyCatalog.load(loader);
});

final playerCatalogProvider = FutureProvider<PlayerCatalog>((ref) {
  final loader = ref.read(assetLoaderProvider);
  return PlayerCatalog.load(loader);
});

final campaignRepositoryProvider = FutureProvider<CampaignRepository>((ref) async {
  final loader = ref.read(assetLoaderProvider);
  final repo = CampaignRepository(loader);
  await repo.load();
  return repo;
});

// ---- Derived data ----

final allCampaignsProvider = FutureProvider<List<CampaignDefinition>>((ref) async {
  final repo = await ref.watch(campaignRepositoryProvider.future);
  return repo.getAllCampaigns();
});

final campaignByIdProvider =
    FutureProvider.family<CampaignDefinition, String>((ref, id) async {
  final repo = await ref.watch(campaignRepositoryProvider.future);
  return repo.getCampaignById(id);
});

final missionsForCampaignProvider =
    FutureProvider.family<List<MissionDefinition>, String>((ref, campaignId) async {
  final repo = await ref.watch(campaignRepositoryProvider.future);
  return repo.getMissionsForCampaign(campaignId);
});

final missionByIdProvider =
    FutureProvider.family<MissionDefinition, String>((ref, missionId) async {
  final repo = await ref.watch(campaignRepositoryProvider.future);
  return repo.getMissionById(missionId);
});

final enemyDefinitionProvider =
    FutureProvider.family<EnemyDefinition, String>((ref, enemyId) async {
  final catalog = await ref.watch(enemyCatalogProvider.future);
  return catalog.getById(enemyId);
});

final playerDefinitionProvider =
    FutureProvider.family<PlayerDefinition, String>((ref, playerId) async {
  final catalog = await ref.watch(playerCatalogProvider.future);
  return catalog.getById(playerId);
});

// ---- Multiplayer / identity ----

final identityServiceProvider = Provider<PlayerIdentityService>(
  (_) => PlayerIdentityService(),
);

final roomServiceProvider = Provider<RoomService>(
  (ref) => RoomService(identity: ref.read(identityServiceProvider)),
);

/// Non-null while a networked game is in progress; null for solo play.
final multiplayerInfoProvider = StateProvider<MultiplayerInfo?>((ref) => null);

// ---- Progress / mission unlock ----

final progressRepositoryProvider = Provider<ProgressRepository>(
  (_) => ProgressRepository(),
);

final completedMissionsProvider =
    AsyncNotifierProvider<CompletedMissionsNotifier, Set<String>>(
  CompletedMissionsNotifier.new,
);

class CompletedMissionsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() =>
      ref.read(progressRepositoryProvider).loadCompletedMissions();

  Future<void> markCompleted(String missionId) async {
    await ref.read(progressRepositoryProvider).markMissionCompleted(missionId);
    state = AsyncData({...state.value ?? {}, missionId});
  }
}
