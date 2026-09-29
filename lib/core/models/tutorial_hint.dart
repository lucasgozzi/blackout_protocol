import 'package:flutter/material.dart';

/// One row in the visual legend shown below the hint text.
/// [emoji] matches the icon rendered by ItemComponent on the game board.
/// [color] is the glow/border color in hex format (e.g. "#FFAA00").
@immutable
class TutorialHintIcon {
  final String emoji;
  final Color color;
  final String label;

  const TutorialHintIcon({
    required this.emoji,
    required this.color,
    required this.label,
  });

  factory TutorialHintIcon.fromJson(Map<String, dynamic> json) {
    final hex = (json['color'] as String).replaceFirst('#', '');
    final argb = int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return TutorialHintIcon(
      emoji: json['emoji'] as String,
      color: Color(argb),
      label: json['label'] as String,
    );
  }
}

/// A single tutorial hint shown as a blocking modal the first time a
/// specific in-game action occurs.
///
/// Triggers (stored as plain strings so JSON needs no code-gen):
///   mission_start   — fires immediately when the session starts
///   first_move      — fires on the first player movement
///   first_attack    — fires on the first attack
///   first_search    — fires on the first search action
///   first_open_door — fires when a door is opened for the first time
///   first_enemy_phase — fires at the start of the first enemy phase
///   first_spawn     — fires when enemies appear on the board for the first time
///   first_trade     — fires on the first item trade between players
@immutable
class TutorialHint {
  final String id;
  final String trigger;
  final String title;
  final String message;
  /// Optional visual legend — each entry maps an in-game icon to a label.
  final List<TutorialHintIcon> icons;

  const TutorialHint({
    required this.id,
    required this.trigger,
    required this.title,
    required this.message,
    this.icons = const [],
  });

  factory TutorialHint.fromJson(Map<String, dynamic> json) => TutorialHint(
        id: json['id'] as String,
        trigger: json['trigger'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        icons: (json['icons'] as List<dynamic>? ?? [])
            .map((e) => TutorialHintIcon.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
