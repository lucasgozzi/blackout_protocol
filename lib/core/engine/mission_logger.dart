/// Accumulates a detailed mission log that can be dumped and shared for debugging.
/// Singleton — reset at the start of each session.
class MissionLogger {
  MissionLogger._();
  static final MissionLogger instance = MissionLogger._();

  final List<String> _entries = [];
  int _round = 0;

  void reset() {
    _entries.clear();
    _round = 0;
  }

  void roundStart(int round) {
    _round = round;
    _section('ROUND $round');
  }

  // ---- Player actions ----

  void playerMove(String player, String from, String to) =>
      _log('MOVE', '$player: $from → $to');

  void playerAttack({
    required String player,
    required String weapon,
    required List<int> rolls,
    required int hitValue,
    required int hits,
    required List<String> killed,
    required List<String> wounded,
    required bool friendlyFire,
  }) {
    final rollStr = rolls.join(',');
    final hitStr  = rolls.map((r) => r >= hitValue ? '[$r]' : '$r').join(' ');
    _log('ATTACK', '$player w/$weapon | rolls: $hitStr | hits: $hits/${rolls.length}');
    for (final k in killed)    _log('KILL',    '  killed: $k');
    for (final w in wounded)   _log('FF',      '  friendly fire: $w');
    if (friendlyFire && wounded.isEmpty) _log('FF', '  friendly fire (misses)');
  }

  void playerSearch(String player, String? item) =>
      _log('SEARCH', '$player → ${item ?? "nothing"}');

  void playerLoot(String player, String item, String slot) =>
      _log('LOOT', '$player placed $item in $slot');

  void playerDiscardLoot(String player, String item) =>
      _log('LOOT', '$player discarded $item');

  void playerOpenDoor(String player, String from, String to) =>
      _log('DOOR', '$player opened: $from → $to');

  void endPlayerTurn(String player, int actionsLeft) =>
      _log('END_TURN', '$player ended turn ($actionsLeft actions unused)');

  // ---- Enemy phase ----

  void enemyPhaseStart() => _log('ENEMY_PHASE', 'enemy phase begins');

  void enemyMove(String enemy, String instanceId, String from, String to) =>
      _log('E_MOVE', '$enemy [$instanceId]: $from → $to');

  void enemyAttack({
    required String enemy,
    required String instanceId,
    required String target,
    required String dangerBefore,
    required String dangerAfter,
    required bool eliminated,
  }) {
    final result = eliminated
        ? 'ELIMINATED'
        : '$dangerBefore → $dangerAfter';
    _log('E_ATTACK', '$enemy [$instanceId] attacks $target: $result');
  }

  void enemyNoAction(String enemy, String instanceId, String reason) =>
      _log('E_IDLE', '$enemy [$instanceId]: $reason');

  // ---- Spawn ----

  void spawn(String zoneId, String enemy, int count) =>
      _log('SPAWN', '${count}× $enemy at $zoneId');

  // ---- Alert ----

  void alertChange(int from, int to) =>
      _log('ALERT', 'level $from → $to');

  // ---- Player state ----

  void playerState(String player, String danger, int xp, int actions, int zonesMoved, int maxZones) =>
      _log('P_STATE', '$player | danger:$danger xp:$xp actions:$actions moves:$zonesMoved/$maxZones');

  // ---- Outcome ----

  void victory() => _section('VICTORY');
  void defeat()  => _section('DEFEAT');

  // ---- Output ----

  String dump() {
    final buf = StringBuffer();
    buf.writeln('=== BLACKOUT PROTOCOL — MISSION LOG ===');
    buf.writeln('rounds: $_round | entries: ${_entries.length}');
    buf.writeln('');
    for (final e in _entries) buf.writeln(e);
    return buf.toString();
  }

  List<String> get entries => List.unmodifiable(_entries);

  // ---- Internal ----

  void _log(String tag, String msg) {
    _entries.add('[R$_round][$tag] $msg');
    // ignore: avoid_print
    print('[BP_LOG][R$_round][$tag] $msg');
  }

  void _section(String label) {
    _entries.add('');
    _entries.add('─── $label ───');
    // ignore: avoid_print
    print('[BP_LOG] ─── $label ───');
  }
}
