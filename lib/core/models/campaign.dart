import 'package:freezed_annotation/freezed_annotation.dart';

part 'campaign.freezed.dart';
part 'campaign.g.dart';

enum CampaignAccess { free, purchased }

@freezed
class CampaignDefinition with _$CampaignDefinition {
  const factory CampaignDefinition({
    required String id,
    required String title,
    required String description,
    required String coverArt,
    required CampaignAccess access,
    required int missionCount,
    required List<String> missionIds, // ordered
    required String storeProductId,   // in-app purchase SKU (empty if free)
    @Default(1) int version,
  }) = _CampaignDefinition;

  factory CampaignDefinition.fromJson(Map<String, dynamic> json) =>
      _$CampaignDefinitionFromJson(json);
}

@freezed
class CampaignProgress with _$CampaignProgress {
  const factory CampaignProgress({
    required String campaignId,
    required String userId,
    required Set<String> completedMissionIds,
    required int totalScore,
    @Default(false) bool isCompleted,
    DateTime? completedAt,
  }) = _CampaignProgress;

  factory CampaignProgress.fromJson(Map<String, dynamic> json) =>
      _$CampaignProgressFromJson(json);
}
