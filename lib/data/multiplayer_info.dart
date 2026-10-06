/// Holds the multiplayer context for the current game session.
/// Set by the lobby before navigating to /game; null in solo play.
class MultiplayerInfo {
  final String roomId;
  final bool isHost;
  /// This device's player UUID inside GameState.players.
  final String myPlayerId;

  const MultiplayerInfo({
    required this.roomId,
    required this.isHost,
    required this.myPlayerId,
  });
}
