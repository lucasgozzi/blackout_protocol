import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';

import '../core/engine/enemy_turn_script.dart';
import '../core/models/game_state.dart';

/// RTDB structure under rooms/{roomId}/:
///   game_state      — JSON of GameState, written by host after every action
///   cinematic       — JSON of EnemyTurnScript, written by host on enemy phase
///   pending_loot    — {lootId, playerId}, written by host when loot is found
///   pending_action  — {actionId, type, payload, by}, written by client for host
class GameSyncService {
  final String roomId;
  final bool isHost;
  final String myUserId;
  final FirebaseDatabase _db;

  GameSyncService({
    required this.roomId,
    required this.isHost,
    required this.myUserId,
    FirebaseDatabase? db,
  }) : _db = db ?? FirebaseDatabase.instance;

  DatabaseReference get _root => _db.ref('rooms/$roomId');

  // ── Host → clients ─────────────────────────────────────────────────────────

  Future<void> broadcastGameState(GameState state) =>
      _root.child('game_state').set(_sanitize(state.toJson()));

  Future<void> clearCinematic() =>
      _root.child('cinematic').remove();

  Future<void> clearPendingLoot() =>
      _root.child('pending_loot').remove();

  /// Atomically broadcasts game state plus optional cinematic/loot payloads.
  Future<void> broadcastFull({
    required GameState gameState,
    EnemyTurnScript? cinematic,
    ({String lootId, String playerId})? pendingLoot,
  }) async {
    final updates = <String, dynamic>{'game_state': _sanitize(gameState.toJson())};
    if (cinematic != null) updates['cinematic'] = _sanitize(cinematic.toJson());
    if (pendingLoot != null) {
      updates['pending_loot'] = {
        'lootId': pendingLoot.lootId,
        'playerId': pendingLoot.playerId,
      };
    }
    await _root.update(updates);
  }

  /// Converts a Freezed toJson() map into a fully-primitive tree.
  ///
  /// The generated _$$*ImplToJson functions don't call toJson() on nested
  /// Freezed objects (missing explicitToJson: true). Running through
  /// jsonEncode/jsonDecode forces the codec to call toJson() recursively on
  /// every nested object, giving Firebase a plain Map/List/primitive tree.
  static Map<String, dynamic> _sanitize(Map<String, dynamic> raw) =>
      jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;

  // ── Client → host ──────────────────────────────────────────────────────────

  Future<void> submitAction(String type, Map<String, dynamic> payload) =>
      _root.child('pending_action').set({
        'type':    type,
        'payload': payload,
        'by':      myUserId,
      });

  Future<void> clearPendingAction() =>
      _root.child('pending_action').remove();

  // ── Streams ────────────────────────────────────────────────────────────────

  /// Host listens here for client action submissions.
  Stream<({String type, Map<String, dynamic> payload})> get pendingActionStream {
    return _root.child('pending_action').onValue
        .where((e) => e.snapshot.value != null)
        .map((e) {
          final raw = Map<String, dynamic>.from(
              e.snapshot.value as Map<Object?, Object?>);
          final payload = Map<String, dynamic>.from(
              (raw['payload'] as Map<Object?, Object?>?) ?? {});
          return (type: raw['type'] as String, payload: payload);
        });
  }

  /// Clients listen here for host broadcasts of game state.
  Stream<GameState> get gameStateStream {
    return _root.child('game_state').onValue
        .where((e) => e.snapshot.value != null)
        .map((e) {
          final raw = Map<String, dynamic>.from(
              e.snapshot.value as Map<Object?, Object?>);
          return GameState.fromJson(raw);
        });
  }

  /// Clients listen here for enemy cinematic scripts.
  Stream<EnemyTurnScript> get cinematicStream {
    return _root.child('cinematic').onValue
        .where((e) => e.snapshot.value != null)
        .map((e) {
          final raw = Map<String, dynamic>.from(
              e.snapshot.value as Map<Object?, Object?>);
          return EnemyTurnScript.fromJson(raw);
        });
  }

  /// Clients listen here for pending-loot notifications from host.
  Stream<({String lootId, String playerId})?> get pendingLootStream {
    return _root.child('pending_loot').onValue.map((e) {
      if (e.snapshot.value == null) return null;
      final raw = Map<String, dynamic>.from(
          e.snapshot.value as Map<Object?, Object?>);
      return (
        lootId:   raw['lootId'] as String,
        playerId: raw['playerId'] as String,
      );
    });
  }

  /// Clean up the game-sync nodes when the session ends.
  Future<void> dispose() async {
    await _root.child('game_state').remove();
    await _root.child('cinematic').remove();
    await _root.child('pending_loot').remove();
    await _root.child('pending_action').remove();
  }
}
