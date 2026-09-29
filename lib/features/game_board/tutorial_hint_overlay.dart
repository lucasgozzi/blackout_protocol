import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/tutorial_hint.dart';

/// Blocking modal overlay that displays a tutorial hint.
/// The game board stays visible but dimmed behind it.
/// Dismissed by tapping the button, which calls notifier.dismissHint().
class TutorialHintOverlay extends ConsumerWidget {
  final TutorialHint hint;

  const TutorialHintOverlay({super.key, required this.hint});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3ECFCF), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D1117),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school_outlined, color: Color(0xFF3ECFCF), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hint.title,
                          style: const TextStyle(
                            color: Color(0xFF3ECFCF),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    hint.message,
                    style: const TextStyle(
                      color: Color(0xFFCDD5E0),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),

                // Icon legend (optional)
                if (hint.icons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      children: [
                        const Divider(color: Color(0xFF2A3040), height: 24),
                        ...hint.icons.map(
                          (ic) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                // Glow badge matching the game board style.
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ic.color.withValues(alpha: 0.15),
                                    border: Border.all(
                                      color: ic.color.withValues(alpha: 0.7),
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    ic.emoji,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    ic.label,
                                    style: const TextStyle(
                                      color: Color(0xFFCDD5E0),
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3ECFCF),
                      foregroundColor: const Color(0xFF0D1117),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        ref.read(gameSessionProvider.notifier).dismissHint(),
                    child: const Text(
                      'Entendido',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
