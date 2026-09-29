import 'package:flutter/material.dart';
import '../../core/engine/game_context.dart';

/// Development-only screen. Accessible via:
///   - Shake gesture (debug builds)
///   - Route /dev (debug builds only)
///
/// Allows jumping into any preset game state instantly.
class DevLauncherScreen extends StatefulWidget {
  final void Function(GameContext context) onLaunch;

  const DevLauncherScreen({super.key, required this.onLaunch});

  @override
  State<DevLauncherScreen> createState() => _DevLauncherScreenState();
}

class _DevLauncherScreenState extends State<DevLauncherScreen> {
  GameContextPreset _selectedPreset = GameContextPreset.missionStart;
  String _customMissionId = 'c01_m01_fuel_depot';
  int _customRound = 1;
  int _customAlertLevel = 0;

  static const _presetMeta = {
    GameContextPreset.missionStart: (
      label: 'Mission Start',
      description: 'Round 1, alert 0, no enemies',
      icon: Icons.play_arrow,
      color: Colors.green,
    ),
    GameContextPreset.midMission: (
      label: 'Mid Mission',
      description: 'Round 5, alert 5, scattered enemies',
      icon: Icons.radio_button_checked,
      color: Colors.blue,
    ),
    GameContextPreset.highAlert: (
      label: 'High Alert',
      description: 'Round 9, alert 9, board crowded',
      icon: Icons.warning,
      color: Colors.orange,
    ),
    GameContextPreset.bossEncounter: (
      label: 'Boss Encounter',
      description: 'SENTINEL-9 active, low resources',
      icon: Icons.dangerous,
      color: Colors.red,
    ),
    GameContextPreset.nearVictory: (
      label: 'Near Victory',
      description: 'Objectives complete, need to extract',
      icon: Icons.emoji_events,
      color: Colors.amber,
    ),
    GameContextPreset.nearDefeat: (
      label: 'Near Defeat',
      description: 'High alert, critical players',
      icon: Icons.crisis_alert,
      color: Colors.deepOrange,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Row(
          children: [
            Icon(Icons.bug_report, color: Color(0xFF00FF88)),
            SizedBox(width: 8),
            Text(
              'DEV LAUNCHER',
              style: TextStyle(
                color: Color(0xFF00FF88),
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildWarningBanner(),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 2, child: _buildPresetList()),
                const VerticalDivider(color: Color(0xFF333333)),
                Expanded(flex: 3, child: _buildPresetDetail()),
              ],
            ),
          ),
          _buildLaunchBar(),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A0000),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Text(
        '⚠  DEBUG BUILD — this screen does not appear in release',
        style: TextStyle(color: Color(0xFFFF4444), fontSize: 11, fontFamily: 'monospace'),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPresetList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('PRESETS', style: TextStyle(color: Color(0xFF666666), fontSize: 11, letterSpacing: 1)),
        ),
        ..._presetMeta.entries.map((entry) {
          final isSelected = _selectedPreset == entry.key;
          final meta = entry.value;
          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: const Color(0xFF1A2A1A),
            leading: Icon(meta.icon, color: isSelected ? meta.color : const Color(0xFF444444), size: 20),
            title: Text(
              meta.label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF888888),
                fontSize: 13,
              ),
            ),
            onTap: () => setState(() => _selectedPreset = entry.key),
          );
        }),
      ],
    );
  }

  Widget _buildPresetDetail() {
    final meta = _presetMeta[_selectedPreset]!;
    final ctx = GameContext.preset(_selectedPreset);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(meta.icon, color: meta.color, size: 24),
              const SizedBox(width: 8),
              Text(meta.label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(meta.description, style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
          const SizedBox(height: 16),
          _buildStateTable(ctx),
          const SizedBox(height: 16),
          _buildPlayersList(ctx),
          const SizedBox(height: 12),
          _buildEnemiesList(ctx),
        ],
      ),
    );
  }

  Widget _buildStateTable(GameContext ctx) {
    return _CodeBlock(
      label: 'GAME STATE',
      children: [
        _row('mission',     ctx.missionId),
        _row('round',       ctx.round.toString()),
        _row('alertLevel',  '${ctx.alertLevel} / 10'),
        _row('phase',       ctx.phase.name),
        _row('players',     ctx.players.length.toString()),
        _row('enemies',     ctx.enemies.length.toString()),
      ],
    );
  }

  Widget _buildPlayersList(GameContext ctx) {
    return _CodeBlock(
      label: 'PLAYERS',
      children: ctx.players.map((p) => _row(
        p.definitionId,
        'xp:${p.xp} | zone:${p.zoneId}',
      )).toList(),
    );
  }

  Widget _buildEnemiesList(GameContext ctx) {
    return _CodeBlock(
      label: 'ENEMIES',
      children: ctx.enemies.isEmpty
          ? [_row('none', '')]
          : ctx.enemies.map((e) => _row(
              e.definitionId,
              'hp:${e.currentHp} | zone:${e.zoneId}',
            )).toList(),
    );
  }

  Widget _row(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(key, style: const TextStyle(color: Color(0xFF00AAFF), fontSize: 12, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Color(0xFF333333))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FF88),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          icon: const Icon(Icons.rocket_launch),
          label: const Text('LAUNCH WITH PRESET', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          onPressed: () => widget.onLaunch(GameContext.preset(_selectedPreset)),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _CodeBlock({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0A),
            border: Border.all(color: const Color(0xFF333333)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
