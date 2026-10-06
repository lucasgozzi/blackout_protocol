import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/engine/game_session_notifier.dart';
import '../../core/models/campaign.dart';
import '../../core/models/mission.dart';
import '../../data/asset_loader.dart';
import '../../data/game_sync_service.dart';
import '../../data/map_loader.dart';
import '../../data/multiplayer_info.dart';
import '../../data/providers.dart';
import '../../data/room_service.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _playersStreamProvider =
    StreamProvider.family<Map<String, RoomPlayer>, String>(
  (ref, roomId) => ref.read(roomServiceProvider).playersStream(roomId),
);

final _roomStatusProvider =
    StreamProvider.family<String, String>(
  (ref, roomId) => ref.read(roomServiceProvider).statusStream(roomId),
);

// Flat list of (campaign, mission) pairs for the host's mission picker.
final _allMissionsProvider =
    FutureProvider<List<(CampaignDefinition, MissionDefinition)>>((ref) async {
  final campaigns = await ref.watch(allCampaignsProvider.future);
  final result = <(CampaignDefinition, MissionDefinition)>[];
  for (final c in campaigns) {
    final missions = await ref.read(missionsForCampaignProvider(c.id).future);
    for (final m in missions) {
      result.add((c, m));
    }
  }
  return result;
});

// ── Operator catalog (static, used for draft UI) ─────────────────────────────

const _availableOperators = [
  _OperatorInfo('scout_aria',    'Aria',  'INFILTRADOR', Color(0xFF00BBFF)),
  _OperatorInfo('engineer_rex',  'Rex',   'ENGENHEIRO',  Color(0xFFFFB800)),
  _OperatorInfo('medic_nova',    'Nova',  'MÉDICO',      Color(0xFF00FF88)),
  _OperatorInfo('soldier_kai',   'Kai',   'SOLDADO',     Color(0xFFFF5533)),
];

class _OperatorInfo {
  final String id;
  final String name;
  final String roleLabel;
  final Color color;
  const _OperatorInfo(this.id, this.name, this.roleLabel, this.color);
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // After creating/joining a room, this is set.
  String? _roomId;
  bool    _isHost = false;

  // Host picks a mission before starting.
  String? _selectedMissionId;
  String? _selectedMissionTitle;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Pre-fill with the identity default name.
    final identity = ref.read(identityServiceProvider);
    _nameCtrl.text = identity.displayName;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _createRoom() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome de operador.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rooms = ref.read(roomServiceProvider);
      // Lobby starts without a specific mission; mission is selected in-room.
      final roomId = await rooms.createRoom(
        campaignId: '',
        missionId:  '',
        displayName: name,
      );
      setState(() { _roomId = roomId; _isHost = true; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _joinRoom() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome de operador.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Código deve ter 6 caracteres.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rooms = ref.read(roomServiceProvider);
      await rooms.joinRoom(roomId: code, displayName: name);
      setState(() { _roomId = code; _isHost = false; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _selectOperator(String operatorId) async {
    if (_roomId == null) return;
    await ref.read(roomServiceProvider).selectOperator(_roomId!, operatorId);
  }

  Future<void> _startGame(Map<String, RoomPlayer> players) async {
    if (_roomId == null) return;
    if (_selectedMissionId == null) {
      setState(() => _error = 'Escolha uma missão antes de iniciar.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // 1. Load mission definition.
      final mission = await ref.read(missionByIdProvider(_selectedMissionId!).future);

      // 2. Resolve player start zones from map data.
      final mapId = mission.mapAsset
          .split('/').last.replaceAll('.tmj', '').replaceAll('.json', '');
      List<String> startZoneIds = [];
      List<String> spawnZones   = [];
      try {
        final mapData = await MapLoader(FlutterAssetLoader()).load(mapId);
        startZoneIds = mapData.playerStartPositions.map((s) => s.zoneId).toList();
        spawnZones   = mapData.globalSpawnZoneIds.toList();
      } catch (_) {}

      // 3. Build ordered player list (host first, then others in join order).
      final orderedPlayers = players.values.toList();
      final playerCatalog  = await ref.read(playerCatalogProvider.future);
      final playerDefs     = orderedPlayers
          .map((p) => playerCatalog.getById(p.operatorId!))
          .toList();

      // 4. Init and start mission on the notifier.
      final enemyCatalog = await ref.read(enemyCatalogProvider.future);
      final notifier = ref.read(gameSessionProvider.notifier);
      notifier.init(enemyCatalog);
      notifier.startMission(mission, playerDefs,
          startZoneIds: startZoneIds, spawnZones: spawnZones);

      // 5. Map userId → GameState player UUID.
      final gameState = ref.read(gameSessionProvider)!.game;
      final assignments = <String, String>{};
      for (var i = 0; i < orderedPlayers.length; i++) {
        assignments[orderedPlayers[i].userId] = gameState.players[i].playerId;
      }

      // 6. Atomically write initial state + assignments + status to RTDB.
      await ref.read(roomServiceProvider).writeGameStart(
        roomId:      _roomId!,
        gameState:   gameState,
        assignments: assignments,
        missionId:   mission.id,
      );

      // 7. Wire GameSyncService to the notifier.
      final identity = ref.read(identityServiceProvider);
      final myUserId = identity.currentUserId ?? '';
      final myPlayerId = assignments[myUserId]!;
      final syncService = GameSyncService(
        roomId: _roomId!, isHost: true, myUserId: myUserId);
      notifier.configureMp(syncService, isHost: true, myPlayerId: myPlayerId);

      // 8. Store multiplayer context for the game board.
      ref.read(multiplayerInfoProvider.notifier).state = MultiplayerInfo(
        roomId: _roomId!, isHost: true, myPlayerId: myPlayerId);

      if (mounted) context.go('/game');
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Client bootstrap: called when status changes to 'playing' on a non-host.
  Future<void> _clientBootstrap() async {
    if (_roomId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final identity  = ref.read(identityServiceProvider);
      final myUserId  = identity.currentUserId ?? '';
      final rooms     = ref.read(roomServiceProvider);

      // 1. Fetch our player UUID and the initial game state.
      final myPlayerId = await rooms.getMyPlayerAssignment(_roomId!, myUserId);
      final gameState  = await rooms.getInitialGameState(_roomId!);

      // 2. Load mission definition.
      final mission = await ref.read(missionByIdProvider(gameState.missionId).future);

      // 3. Init notifier and bootstrap session from network state.
      final enemyCatalog = await ref.read(enemyCatalogProvider.future);
      final notifier = ref.read(gameSessionProvider.notifier);
      notifier.init(enemyCatalog);
      notifier.importBootstrap(gameState, mission);

      // 4. Wire GameSyncService.
      final syncService = GameSyncService(
        roomId: _roomId!, isHost: false, myUserId: myUserId);
      notifier.configureMp(syncService, isHost: false, myPlayerId: myPlayerId);

      // 5. Store multiplayer context.
      ref.read(multiplayerInfoProvider.notifier).state = MultiplayerInfo(
        roomId: _roomId!, isHost: false, myPlayerId: myPlayerId);

      if (mounted) context.go('/game');
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _leaveRoom() async {
    if (_roomId != null) {
      await ref.read(roomServiceProvider).leaveRoom(_roomId!);
    }
    ref.read(multiplayerInfoProvider.notifier).state = null;
    setState(() {
      _roomId = null;
      _isHost = false;
      _selectedMissionId    = null;
      _selectedMissionTitle = null;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_roomId != null) return _buildRoom();
    return _buildEntrance();
  }

  // ── Entrance (create / join tabs) ─────────────────────────────────────────

  Widget _buildEntrance() {
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF00FF88)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'MULTIJOGADOR',
          style: TextStyle(
            color: Color(0xFF00FF88),
            fontFamily: 'monospace',
            letterSpacing: 2,
            fontSize: 14,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: const Color(0xFF00FF88),
          labelColor: const Color(0xFF00FF88),
          unselectedLabelColor: const Color(0xFF555566),
          labelStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            letterSpacing: 0.1,
          ),
          tabs: const [
            Tab(text: 'CRIAR SALA'),
            Tab(text: 'ENTRAR NA SALA'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildCreateTab(),
            _buildJoinTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameField(),
          const SizedBox(height: 32),
          if (_error != null) _errorBox(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: _btnStyle(const Color(0xFF00FF88)),
              onPressed: _loading ? null : _createRoom,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'CRIAR SALA',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _nameField(),
          const SizedBox(height: 20),
          _label('CÓDIGO DA SALA'),
          const SizedBox(height: 6),
          TextField(
            controller: _codeCtrl,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 22,
              letterSpacing: 0.25,
            ),
            decoration: _inputDecoration('ABC123'),
          ),
          const SizedBox(height: 24),
          if (_error != null) _errorBox(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: _btnStyle(const Color(0xFF00AAFF)),
              onPressed: _loading ? null : _joinRoom,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'ENTRAR',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Room view ─────────────────────────────────────────────────────────────

  Widget _buildRoom() {
    final playersAsync = ref.watch(_playersStreamProvider(_roomId!));

    // Navigate when game starts. Host already navigated directly; clients bootstrap here.
    ref.listen(_roomStatusProvider(_roomId!), (_, status) {
      if (status.valueOrNull == 'playing' && context.mounted && !_isHost) {
        _clientBootstrap();
      }
    });

    final myUid = ref.read(identityServiceProvider).currentUserId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF555566)),
          onPressed: () async {
            await _leaveRoom();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SALA',
              style: TextStyle(
                color: Color(0xFF00FF88),
                fontFamily: 'monospace',
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
            Text(
              _roomId!,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, color: Color(0xFF555566)),
            tooltip: 'Copiar código',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _roomId!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Código copiado',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: playersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00FF88)),
        ),
        error: (e, _) => Center(
          child: Text(
            'Erro: $e',
            style: const TextStyle(color: Colors.red, fontFamily: 'monospace'),
          ),
        ),
        data: (players) {
          final myPlayer = players[myUid];
          final takenOperators = players.values
              .where((p) => p.userId != myUid && p.operatorId != null)
              .map((p) => p.operatorId!)
              .toSet();
          final allOperatorsReady = players.values.every((p) => p.operatorId != null);
          final allReady = allOperatorsReady && _selectedMissionId != null;

          return SafeArea(
            child: Column(
              children: [
                // Player list + operator draft + mission selector
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionLabel('JOGADORES (${players.length}/4)'),
                      const SizedBox(height: 8),
                      ...players.values.map(
                        (p) => _PlayerCard(
                          player: p,
                          isMe:   p.userId == myUid,
                          isHost: _isHost && p.userId == myUid,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionLabel('ESCOLHA SEU OPERADOR'),
                      const SizedBox(height: 8),
                      ...(_availableOperators.map((op) {
                        final taken  = takenOperators.contains(op.id);
                        final mine   = myPlayer?.operatorId == op.id;
                        return _OperatorTile(
                          info:     op,
                          isMine:   mine,
                          isTaken:  taken && !mine,
                          onTap:    taken ? null : () => _selectOperator(op.id),
                        );
                      })),
                      const SizedBox(height: 24),
                      // Mission selector (host only)
                      if (_isHost) ...[
                        _sectionLabel('MISSÃO'),
                        const SizedBox(height: 8),
                        _MissionPicker(
                          selectedId:    _selectedMissionId,
                          selectedTitle: _selectedMissionTitle,
                          onPick: (id, title) => setState(() {
                            _selectedMissionId    = id;
                            _selectedMissionTitle = title;
                          }),
                        ),
                      ] else ...[
                        _sectionLabel('MISSÃO'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D1A),
                            border: Border.all(color: const Color(0xFF1A1A2E)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Aguardando o host escolher a missão...',
                            style: TextStyle(
                              color: Color(0xFF444455),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Loading overlay during game start
                if (_loading)
                  const LinearProgressIndicator(
                    color: Color(0xFF00FF88),
                    backgroundColor: Color(0xFF0D0D1A),
                  ),

                // Error
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _errorBox(),
                  ),

                // Bottom bar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D0D1A),
                    border: Border(
                      top: BorderSide(color: Color(0xFF1A1A2E)),
                    ),
                  ),
                  child: _isHost
                      ? SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: _btnStyle(
                              allReady && !_loading
                                  ? const Color(0xFF00FF88)
                                  : const Color(0xFF333333),
                            ),
                            onPressed: (allReady && !_loading)
                                ? () => _startGame(players)
                                : null,
                            child: Text(
                              _loading
                                  ? 'INICIANDO...'
                                  : allReady
                                      ? 'INICIAR MISSÃO'
                                      : 'AGUARDANDO...',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: (allReady && !_loading)
                                    ? Colors.black
                                    : const Color(0xFF555566),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            _loading
                                ? 'Iniciando missão...'
                                : 'Aguardando o host iniciar a missão...',
                            style: const TextStyle(
                              color: Color(0xFF555566),
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _nameField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('SEU NOME DE OPERADOR'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            maxLength: 16,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
            ),
            decoration: _inputDecoration('Ex: Capitão Rex'),
          ),
        ],
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF555566),
          fontFamily: 'monospace',
          fontSize: 11,
          letterSpacing: 0.12,
        ),
      );

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF444455),
          fontFamily: 'monospace',
          fontSize: 11,
          letterSpacing: 0.12,
        ),
      );

  Widget _errorBox() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0808),
          border: Border.all(color: const Color(0xFF440000)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _error!,
          style: const TextStyle(
            color: Color(0xFFFF4444),
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF333344)),
        counterStyle: const TextStyle(color: Color(0xFF333344)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1A1A2E)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF00FF88)),
        ),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
      );

  ButtonStyle _btnStyle(Color bg) => ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      );
}

// ── Player Card ───────────────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  final RoomPlayer player;
  final bool isMe;
  final bool isHost;

  const _PlayerCard({
    required this.player,
    required this.isMe,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    final opInfo = _availableOperators
        .where((o) => o.id == player.operatorId)
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border.all(
          color: isMe
              ? const Color(0xFF00FF88).withValues(alpha: 0.4)
              : const Color(0xFF1A1A2E),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Operator color dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: opInfo?.color ?? const Color(0xFF333344),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 8),
                      const _Chip('VOCÊ', Color(0xFF00FF88)),
                    ],
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      const _Chip('HOST', Color(0xFF00AAFF)),
                    ],
                  ],
                ),
                if (opInfo != null)
                  Text(
                    opInfo.name,
                    style: TextStyle(
                      color: opInfo.color,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  )
                else
                  const Text(
                    'Escolhendo operador...',
                    style: TextStyle(
                      color: Color(0xFF444455),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            player.operatorId != null
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 16,
            color: player.operatorId != null
                ? const Color(0xFF00FF88)
                : const Color(0xFF333344),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 9,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ── Operator Tile ─────────────────────────────────────────────────────────────

class _OperatorTile extends StatelessWidget {
  final _OperatorInfo info;
  final bool isMine;
  final bool isTaken;
  final VoidCallback? onTap;

  const _OperatorTile({
    required this.info,
    required this.isMine,
    required this.isTaken,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isTaken ? const Color(0xFF333344) : info.color;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isTaken ? 0.4 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMine
                ? info.color.withValues(alpha: 0.1)
                : const Color(0xFF0D0D1A),
            border: Border.all(
              color: isMine
                  ? info.color.withValues(alpha: 0.5)
                  : const Color(0xFF1A1A2E),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: effectiveColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    info.name[0],
                    style: TextStyle(
                      color: effectiveColor,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name.toUpperCase(),
                      style: TextStyle(
                        color: isTaken ? const Color(0xFF333344) : Colors.white,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      info.roleLabel,
                      style: TextStyle(
                        color: effectiveColor,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isMine)
                const _Chip('SELECIONADO', Color(0xFF00FF88))
              else if (isTaken)
                const _Chip('OCUPADO', Color(0xFF555566)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mission Picker ────────────────────────────────────────────────────────────

class _MissionPicker extends ConsumerWidget {
  final String? selectedId;
  final String? selectedTitle;
  final void Function(String id, String title) onPick;

  const _MissionPicker({
    required this.selectedId,
    required this.selectedTitle,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(_allMissionsProvider);

    return missionsAsync.when(
      loading: () => const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF00FF88)),
          ),
        ),
      ),
      error: (e, _) => Text('Erro: $e',
          style: const TextStyle(color: Colors.red, fontFamily: 'monospace')),
      data: (missions) {
        if (selectedId != null) {
          return GestureDetector(
            onTap: () => _showPicker(context, missions),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A0D),
                border: Border.all(
                    color: const Color(0xFF00FF88).withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined,
                      color: Color(0xFF00FF88), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedTitle ?? selectedId!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_outlined,
                      color: Color(0xFF444455), size: 14),
                ],
              ),
            ),
          );
        }
        return GestureDetector(
          onTap: () => _showPicker(context, missions),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              border: Border.all(
                  color: const Color(0xFF00FF88).withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.add_circle_outline,
                    color: Color(0xFF00FF88), size: 18),
                SizedBox(width: 10),
                Text('Escolher missão',
                    style: TextStyle(
                      color: Color(0xFF00FF88),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPicker(
    BuildContext context,
    List<(CampaignDefinition, MissionDefinition)> missions,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D0D1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'ESCOLHER MISSÃO',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const Divider(color: Color(0xFF1A1A2E), height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: missions.length,
                itemBuilder: (_, i) {
                  final (campaign, mission) = missions[i];
                  final isSelected = mission.id == selectedId;
                  return ListTile(
                    tileColor: isSelected ? const Color(0xFF0D1A0D) : null,
                    title: Text(
                      mission.title,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF00FF88)
                            : Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      campaign.title,
                      style: const TextStyle(
                        color: Color(0xFF444455),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF00FF88), size: 18)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      onPick(mission.id, mission.title);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
