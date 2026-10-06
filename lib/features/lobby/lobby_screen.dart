import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _isHost = false;

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
    // Ensure all players picked an operator.
    final unready = players.values.where((p) => p.operatorId == null);
    if (unready.isNotEmpty) {
      setState(() => _error = 'Todos precisam escolher um operador.');
      return;
    }
    await ref.read(roomServiceProvider).startGame(_roomId!);
    // Navigation is handled by _roomStatusProvider listener below.
  }

  Future<void> _leaveRoom() async {
    if (_roomId != null) {
      await ref.read(roomServiceProvider).leaveRoom(_roomId!);
    }
    setState(() { _roomId = null; _isHost = false; });
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

    // Navigate to game when host starts.
    ref.listen(_roomStatusProvider(_roomId!), (_, status) {
      if (status.valueOrNull == 'playing' && context.mounted) {
        // Phase 2: wire MultiplayerSessionNotifier before navigating.
        context.go('/game');
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
          final allReady = players.values.every((p) => p.operatorId != null);

          return SafeArea(
            child: Column(
              children: [
                // Player list
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
                    ],
                  ),
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
                              allReady
                                  ? const Color(0xFF00FF88)
                                  : const Color(0xFF333333),
                            ),
                            onPressed: allReady
                                ? () => _startGame(players)
                                : null,
                            child: Text(
                              allReady
                                  ? 'INICIAR MISSÃO'
                                  : 'AGUARDANDO JOGADORES...',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: allReady ? Colors.black : const Color(0xFF555566),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            _isHost
                                ? ''
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
