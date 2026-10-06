import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

import 'identity_service.dart';

/// Possible room statuses stored in RTDB.
enum RoomStatus { lobby, playing, ended }

class RoomPlayer {
  final String userId;
  final String displayName;
  final String? operatorId;
  final bool isReady;

  const RoomPlayer({
    required this.userId,
    required this.displayName,
    this.operatorId,
    required this.isReady,
  });

  factory RoomPlayer.fromMap(String userId, Map<Object?, Object?> data) {
    return RoomPlayer(
      userId:      userId,
      displayName: data['displayName'] as String? ?? 'Operador',
      operatorId:  data['operatorId'] as String?,
      isReady:     data['isReady'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    if (operatorId != null) 'operatorId': operatorId,
    'isReady':     isReady,
  };
}

class RoomService {
  final FirebaseDatabase _db;
  final PlayerIdentityService _identity;

  RoomService({
    FirebaseDatabase? db,
    required PlayerIdentityService identity,
  })  : _db = db ?? FirebaseDatabase.instance,
        _identity = identity;

  DatabaseReference _roomRef(String roomId) =>
      _db.ref('rooms/$roomId');

  // ── Create ──────────────────────────────────────────────────────────────

  Future<String> createRoom({
    required String campaignId,
    required String missionId,
    required String displayName,
  }) async {
    await _identity.ensureSignedIn();
    final uid    = _identity.currentUserId!;
    final roomId = _generateCode();
    final ref    = _roomRef(roomId);

    await ref.set({
      'meta': {
        'hostUserId':  uid,
        'status':      'lobby',
        'campaignId':  campaignId,
        'missionId':   missionId,
        'createdAt':   ServerValue.timestamp,
      },
      'players': {
        uid: RoomPlayer(
          userId:      uid,
          displayName: displayName,
          isReady:     true,
        ).toMap(),
      },
    });

    // Remove player slot on disconnect.
    ref.child('players/$uid').onDisconnect().remove();

    return roomId;
  }

  // ── Join ────────────────────────────────────────────────────────────────

  Future<void> joinRoom({
    required String roomId,
    required String displayName,
  }) async {
    await _identity.ensureSignedIn();
    final uid = _identity.currentUserId!;
    final ref = _roomRef(roomId);

    // Verify room exists and is in lobby state.
    final snap = await ref.child('meta/status').get();
    if (!snap.exists || snap.value != 'lobby') {
      throw Exception('Sala não encontrada ou já iniciada.');
    }

    await ref.child('players/$uid').set(
      RoomPlayer(
        userId:      uid,
        displayName: displayName,
        isReady:     false,
      ).toMap(),
    );

    ref.child('players/$uid').onDisconnect().remove();
  }

  // ── Leave ───────────────────────────────────────────────────────────────

  Future<void> leaveRoom(String roomId) async {
    final uid = _identity.currentUserId;
    if (uid == null) return;
    await _roomRef(roomId).child('players/$uid').remove();
  }

  // ── Update operator selection ────────────────────────────────────────────

  Future<void> selectOperator(String roomId, String operatorId) async {
    final uid = _identity.currentUserId;
    if (uid == null) return;
    await _roomRef(roomId).child('players/$uid').update({
      'operatorId': operatorId,
      'isReady':    true,
    });
  }

  // ── Stream ───────────────────────────────────────────────────────────────

  Stream<Map<String, RoomPlayer>> playersStream(String roomId) {
    return _roomRef(roomId).child('players').onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return {};
      final map = data as Map<Object?, Object?>;
      return {
        for (final entry in map.entries)
          entry.key as String: RoomPlayer.fromMap(
            entry.key as String,
            entry.value as Map<Object?, Object?>,
          ),
      };
    });
  }

  Stream<String> statusStream(String roomId) {
    return _roomRef(roomId)
        .child('meta/status')
        .onValue
        .map((e) => e.snapshot.value as String? ?? 'lobby');
  }

  // ── Start game (host only) ───────────────────────────────────────────────

  Future<void> startGame(String roomId) async {
    await _roomRef(roomId).child('meta/status').set('playing');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
