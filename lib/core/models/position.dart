import 'package:freezed_annotation/freezed_annotation.dart';

part 'position.freezed.dart';
part 'position.g.dart';

@freezed
class GridPosition with _$GridPosition {
  const factory GridPosition({
    required int x,
    required int y,
  }) = _GridPosition;

  factory GridPosition.fromJson(Map<String, dynamic> json) =>
      _$GridPositionFromJson(json);
}
