import 'dart:async';
import 'dart:math' as math;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/models/game_state.dart';
import '../../core/models/mission.dart';
import '../../core/models/zone.dart';
import '../../core/rules/skill_system.dart';
import '../../data/map_loader.dart';
import '../../data/asset_loader.dart';
import 'board_constants.dart';
import 'components/map_tile_component.dart';
import 'components/zone_overlay_component.dart';
import 'components/player_component.dart';
import 'components/enemy_component.dart';
import 'components/item_component.dart';

enum ActionMode { none, move, attack, openDoor }

class GameBoardGame extends FlameGame with TapCallbacks, ScaleDetector {
  GameState gameState;
  final MissionDefinition mission;

  final void Function(String playerId, String zoneId) onMoveToZone;
  final void Function(String playerId, String weaponId, String zoneId) onAttackZone;
  final void Function(String playerId, String? objectiveId)                   onSearch;
  final void Function(String playerId, String objectiveId)                    onInteract;
  final void Function(String playerId, String fromZoneId, String toZoneId)    onOpenDoor;
  void Function(ActionMode mode) onActionModeChanged;

  String? activeWeaponId;

  GameBoardGame({
    required this.gameState,
    required this.mission,
    required this.onMoveToZone,
    required this.onAttackZone,
    required this.onSearch,
    required this.onInteract,
    required this.onOpenDoor,
    required this.onActionModeChanged,
  });

  late MapData  _mapData;
  late World    _world;
  late CameraComponent _cam;

  // Zone overlays (one per zone across all tiles)
  final Map<String, ZoneOverlayComponent> _zoneOverlays = {};
  // Pieces
  final Map<String, PlayerComponent> _players = {};
  final Map<String, EnemyComponent>  _enemies = {};
  final Map<String, ItemComponent>   _items   = {};

  ActionMode  _actionMode = ActionMode.none;
  String?     _selectedPlayerId;
  String?     _selectedZoneId;
  Set<String> _reachableZoneIds  = {};
  Set<String> _attackableZoneIds = {};
  Set<String> _doorZoneIds       = {}; // adjacent zones with closed door

  bool   _loaded = false;
  double _zoom   = 1.2;
  Vector2 _panStart = Vector2.zero();

  static const double _zoomMin  = 0.3;
  static const double _zoomMax  = 3.0;
  static const double _zoomStep = 0.25;

  ActionMode get currentActionMode => _actionMode;
  String?    get selectedPlayerId  => _selectedPlayerId;
  bool       get hasDoorAdjacent  => _doorZoneIds.isNotEmpty;
  double     get zoom              => _zoom;

  void zoomIn()  => _applyZoom(_zoom + _zoomStep);
  void zoomOut() => _applyZoom(_zoom - _zoomStep);

  void _applyZoom(double newZoom) {
    _zoom = newZoom.clamp(_zoomMin, _zoomMax);
    _cam.viewfinder.zoom = _zoom;
  }

  /// Smoothly pan the camera to a world position over [ms] milliseconds.
  Future<void> animateCameraTo(double wx, double wy, {int ms = 600}) async {
    final start = _cam.viewfinder.position.clone();
    final end   = Vector2(wx, wy);
    final steps = (ms / 16).ceil();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      // Ease-in-out cubic
      final eased = t < 0.5 ? 4 * t * t * t : 1 - math.pow((-2 * t + 2).abs(), 3) / 2;
      _cam.viewfinder.position = start + (end - start) * eased;
      await Future.delayed(const Duration(milliseconds: 16));
    }
    _cam.viewfinder.position = end;
  }

  // ---- Movement trail & enemy slide (cinematic) ----

  _MovementTrailComponent? _trailComponent;

  /// Draw a dashed arrow from (fx,fy) to (tx,ty) in world space.
  void showMovementTrail(
      String instanceId, double fx, double fy, double tx, double ty) {
    _trailComponent?.removeFromParent();
    final trail = _MovementTrailComponent(
      from: Vector2(fx, fy), to: Vector2(tx, ty));
    _trailComponent = trail;
    _world.add(trail);
  }

  // Multiple trails for a group move — keyed by instanceId.
  final Map<String, _MovementTrailComponent> _groupTrails = {};

  void showGroupTrails(List<({String instanceId, double fx, double fy, double tx, double ty})> moves) {
    clearGroupTrails();
    for (final m in moves) {
      final trail = _MovementTrailComponent(
          from: Vector2(m.fx, m.fy), to: Vector2(m.tx, m.ty));
      _groupTrails[m.instanceId] = trail;
      _world.add(trail);
    }
  }

  void clearGroupTrails() {
    for (final t in _groupTrails.values) t.removeFromParent();
    _groupTrails.clear();
  }

  /// Instantly place an enemy component at a world position (before slide).
  void placeEnemyAt(String instanceId, double wx, double wy) {
    _enemies[instanceId]?.position = Vector2(wx, wy);
  }

  void clearMovementTrail() {
    _trailComponent?.removeFromParent();
    _trailComponent = null;
  }

  /// Smoothly slide an enemy component from its current position to (tx, ty),
  /// keeping the camera locked on it throughout the animation.
  Future<void> slideEnemyTo(String instanceId, int tx, int ty,
      {bool followCamera = false}) async {
    final comp = _enemies[instanceId];
    if (comp == null) return;

    final start = comp.position.clone();
    final end   = Vector2(tx.toDouble(), ty.toDouble());
    const n     = 24;
    for (var i = 1; i <= n; i++) {
      final t    = i / n;
      final ease = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2).abs() * (-2 * t + 2).abs() / 2;
      comp.position = start + (end - start) * ease;
      if (followCamera) _cam.viewfinder.position = comp.position.clone();
      await Future.delayed(const Duration(milliseconds: 16));
    }
    comp.position = end;
    if (followCamera) _cam.viewfinder.position = end.clone();
  }

  /// Slide all enemies in a group simultaneously, camera follows the centroid.
  Future<void> slideGroupTo(List<({String instanceId, double tx, double ty})> moves) async {
    if (moves.isEmpty) return;

    // Build start positions and ends.
    final comps = <({EnemyComponent comp, Vector2 start, Vector2 end})>[];
    for (final m in moves) {
      final comp = _enemies[m.instanceId];
      if (comp == null) continue;
      comps.add((comp: comp, start: comp.position.clone(),
                 end: Vector2(m.tx, m.ty)));
    }
    if (comps.isEmpty) return;

    const n = 24;
    for (var i = 1; i <= n; i++) {
      final t    = i / n;
      final ease = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2).abs() * (-2 * t + 2).abs() / 2;

      double cx = 0, cy = 0;
      for (final c in comps) {
        c.comp.position = c.start + (c.end - c.start) * ease;
        cx += c.comp.position.x;
        cy += c.comp.position.y;
      }
      // Camera follows centroid of the group.
      _cam.viewfinder.position = Vector2(cx / comps.length, cy / comps.length);
      await Future.delayed(const Duration(milliseconds: 16));
    }
    for (final c in comps) {
      c.comp.position = c.end;
    }
    if (comps.isNotEmpty) {
      final cx = comps.map((c) => c.end.x).reduce((a, b) => a + b) / comps.length;
      final cy = comps.map((c) => c.end.y).reduce((a, b) => a + b) / comps.length;
      _cam.viewfinder.position = Vector2(cx, cy);
    }
  }

  @override
  Future<void> onLoad() async {
    final mapId = mission.mapAsset
        .split('/').last.replaceAll('.tmj','').replaceAll('.json','');

    try {
      _mapData = await MapLoader(FlutterAssetLoader()).load(mapId);
      // ignore: avoid_print
      print('[Board] Map loaded: ${_mapData.tiles.length} tiles, mapId=$mapId');
    } catch (e, st) {
      // ignore: avoid_print
      print('[Board] Map load FAILED mapId=$mapId: $e\n$st');
      _mapData = MapData(tiles: [], tilePixelSize: 200, globalSpawnZoneIds: []);
    }

    _world = World();
    _cam   = CameraComponent(world: _world);
    _cam.viewfinder.zoom = _zoom;

    addAll([_world, _cam]);

    await _buildMap();
    _buildZoneOverlays();
    _buildItems();
    _syncPieces();
    _centerCamera();
    _autoSelectActivePlayer();

    _loaded = true;
  }

  // When true, syncState skips repositioning enemy components so the
  // cinematic can slide them without being overridden each frame.
  bool freezeEnemySync = false;

  void syncState(GameState newState) {
    if (!_loaded) return;
    final prevActiveId = gameState.activePlayerId;
    gameState = newState;
    _syncPieces();
    _syncItems();
    _syncZoneInfo();

    final activeChanged = newState.activePlayerId != prevActiveId;
    if (activeChanged || _selectedPlayerId == null) {
      _clearSelection();
      _autoSelectActivePlayer();
    } else {
      // Same active player — recompute reachable from their new position
      // (they may have moved one zone and still have moves left).
      _reselect();
    }
  }

  void _reselect() {
    try {
      final player = gameState.players.firstWhere(
        (p) => p.playerId == gameState.activePlayerId && !p.isEliminated,
      );
      _selectedPlayerId  = player.playerId;
      _selectedZoneId    = player.zoneId;
      _reachableZoneIds  = _computeReachable(_selectedZoneId);
      _attackableZoneIds = _computeAttackable(_selectedZoneId);
      _doorZoneIds       = _computeDoorZones(_selectedZoneId);
      _updateOverlays();
      onActionModeChanged(_actionMode);
    } catch (_) {
      _clearSelection();
    }
  }

  // ---- Map rendering ----

  Future<void> _buildMap() async {
    for (final tile in _mapData.tiles) {
      final r = _mapData.tileWorldRect(tile);
      final comp = MapTileComponent(
        tileId:    tile.id,
        imageName: tile.image,
        position:  Vector2(r.x, r.y),
        size:      Vector2(r.w, r.h),
        onTap:     (x, y) => _onMapTapped(tile.id, x, y),
      );
      _world.add(comp);
    }
  }

  void _buildZoneOverlays() {
    for (final tile in _mapData.tiles) {
      final r = _mapData.tileWorldRect(tile);
      for (final zone in tile.zones) {
        final zx = r.x + zone.rect.x * r.w;
        final zy = r.y + zone.rect.y * r.h;
        final zw = zone.rect.w * r.w;
        final zh = zone.rect.h * r.h;

        final comp = ZoneOverlayComponent(
          zoneId:   zone.id,
          zoneName: zone.name,
          zoneType: zone.type,
          position: Vector2(zx, zy),
          size:     Vector2(zw, zh),
          onTap:    () => _onZoneTapped(zone.id),
        );
        _zoneOverlays[zone.id] = comp;
        _world.add(comp);
      }
    }
  }

  void _buildItems() {
    for (final tile in _mapData.tiles) {
      final r = _mapData.tileWorldRect(tile);
      for (final zone in tile.zones) {
        if (zone.tags.isEmpty) continue;
        final tag = zone.tags.firstWhere((t) => t != 'extraction_zone', orElse: () => '');
        if (tag.isEmpty) continue;
        final center = _mapData.zoneCenter(tile, zone);
        final comp = ItemComponent.world(
          worldX: center.x,
          worldY: center.y,
          tag: tag,
          size: _mapData.tilePixelSize * 0.15,
        );
        _items[zone.id] = comp;
        _world.add(comp);
      }
    }
  }

  void _syncZoneInfo() {
    // Build enemy count per zone id.
    final enemyCountByZone = <String, int>{};
    for (final e in gameState.enemies) {
      if (e.zoneId.isNotEmpty) {
        enemyCountByZone[e.zoneId] = (enemyCountByZone[e.zoneId] ?? 0) + 1;
      }
    }

    final spawnZones = _mapData.globalSpawnZoneIds.toSet();

    for (final entry in _zoneOverlays.entries) {
      final zoneId = entry.key;
      final found  = _mapData.findZone(zoneId);
      final hasObj = found != null && found.zone.tags.any((t) =>
          gameState.objectives.any((o) => !o.isCompleted && (
            o.params['itemId'] == t ||
            o.params['targetTileTag'] == t ||
            o.id == t
          )));

      entry.value.setZoneInfo(
        enemyCount:   enemyCountByZone[zoneId] ?? 0,
        hasObjective: hasObj,
        isSpawnZone:  spawnZones.contains(zoneId),
      );
    }
  }

  void _syncItems() {
    for (final entry in _items.entries) {
      final found = _mapData.findZone(entry.key);
      if (found == null) continue;
      final collected = found.zone.tags.any((tag) =>
          gameState.objectives.any((o) => o.isCompleted && (
            o.params['itemId'] == tag ||
            o.params['targetTileTag'] == tag ||
            o.id == tag
          )));
      entry.value.setCollected(collected);
    }
  }

  // ---- Pieces ----

  void _syncPieces() {
    _syncPlayers();
    _syncEnemies();
  }

  void _syncPlayers() {
    final ids = gameState.players.map((p) => p.playerId).toSet();
    for (final id in _players.keys.toList()) {
      if (!ids.contains(id)) { _players[id]?.removeFromParent(); _players.remove(id); }
    }
    for (final p in gameState.players) {
      if (p.isEliminated) { _players[p.playerId]?.removeFromParent(); _players.remove(p.playerId); continue; }
      final worldPos = worldPosForZone(p.zoneId);
      if (_players.containsKey(p.playerId)) {
        _players[p.playerId]!.updateState(p);
        _players[p.playerId]!.position = worldPos;
      } else {
        final comp = PlayerComponent(
          player: p,
          isActive: p.playerId == gameState.activePlayerId,
          onTap: () => _onPlayerTapped(p.playerId),
        );
        comp.position = worldPos;
        _players[p.playerId] = comp;
        _world.add(comp);
      }
    }
    for (final e in _players.entries) e.value.setActive(e.key == gameState.activePlayerId);
  }

  void _syncEnemies() {
    final ids = gameState.enemies.map((e) => e.instanceId).toSet();
    for (final id in _enemies.keys.toList()) {
      if (!ids.contains(id)) { _enemies[id]?.removeFromParent(); _enemies.remove(id); }
    }
    for (final e in gameState.enemies) {
      if (_enemies.containsKey(e.instanceId)) {
        _enemies[e.instanceId]!.updateState(e);
        if (!freezeEnemySync) {
          _enemies[e.instanceId]!.position = worldPosForZone(e.zoneId);
        }
      } else {
        final comp = EnemyComponent(
          enemy: e,
          onTap: () => _onZoneTapped(e.zoneId),
        );
        comp.position = worldPosForZone(e.zoneId);
        _enemies[e.instanceId] = comp;
        _world.add(comp);
      }
    }

    // Group by (definitionId, zoneId): only the first instance per group is
    // visible; others are hidden. The visible one shows the group count.
    final seen = <String>{};
    final groupCount = <String, int>{};
    for (final e in gameState.enemies) {
      final key = '${e.definitionId}@${e.zoneId}';
      groupCount[key] = (groupCount[key] ?? 0) + 1;
    }
    for (final e in gameState.enemies) {
      final key  = '${e.definitionId}@${e.zoneId}';
      final comp = _enemies[e.instanceId];
      if (comp == null) continue;
      if (!seen.contains(key)) {
        seen.add(key);
        comp.isVisible = true;
        comp.count     = groupCount[key]!;
      } else {
        comp.isVisible = false;
        comp.count     = 1;
      }
    }
  }

  /// Returns the world-space center for [zoneId], or Vector2.zero() if not found.
  Vector2 worldPosForZone(String zoneId) {
    if (!_loaded || zoneId.isEmpty) return Vector2.zero();
    final found = _mapData.findZone(zoneId);
    if (found == null) return Vector2.zero();
    final c = _mapData.zoneCenter(found.tile, found.zone);
    return Vector2(c.x, c.y);
  }

  // ---- Auto-selection ----

  void _autoSelectActivePlayer() {
    if (gameState.phase != GamePhase.playerTurn) return;
    final playerId = gameState.activePlayerId;
    try {
      final player = gameState.players.firstWhere(
        (p) => p.playerId == playerId && !p.isEliminated && p.actionsRemaining > 0,
      );
      _selectedPlayerId  = player.playerId;
      _selectedZoneId    = player.zoneId;
      _actionMode        = ActionMode.none;
      _reachableZoneIds  = _computeReachable(_selectedZoneId);
      _attackableZoneIds = _computeAttackable(_selectedZoneId);
      _doorZoneIds       = _computeDoorZones(_selectedZoneId);
      _updateOverlays();
      onActionModeChanged(ActionMode.none);
    } catch (_) {
      // Player not found or already eliminated — leave selection empty.
    }
  }

  // ---- Action mode ----

  void setActionMode(ActionMode mode) {
    if (_selectedPlayerId == null) return;
    _actionMode = (_actionMode == mode) ? ActionMode.none : mode;
    _updateOverlays();
    onActionModeChanged(_actionMode);
  }

  /// True when the active player can perform a useful search in their current zone.
  /// Zones need either the "item" tag (random loot) or an uncompleted objective.
  bool canSearchCurrentPosition(String playerId) {
    try {
      final player = gameState.players.firstWhere((p) => p.playerId == playerId);
      if (player.actionsRemaining <= 0) return false;
      final zoneId = player.zoneId;
      if (zoneId.isEmpty) return false;
      final found = _mapData.findZone(zoneId);
      if (found == null) return false;
      final tags = found.zone.tags;
      final hasObjective = tags.any((t) => gameState.objectives.any((o) =>
        !o.isCompleted && (
          o.params['itemId'] == t ||
          o.params['targetTileTag'] == t ||
          o.id == t
        )));
      return hasObjective || tags.contains('item');
    } catch (_) {
      return false;
    }
  }

  /// Called directly by the BUSCAR button — searches the player's current tile.
  /// Only works in zones tagged "item" or containing an uncompleted objective.
  void searchCurrentPosition(String playerId) {
    if (gameState.phase != GamePhase.playerTurn) return;
    final player = gameState.players.firstWhere((p) => p.playerId == playerId);
    if (player.actionsRemaining <= 0) return;

    final zoneId = player.zoneId;
    if (zoneId.isEmpty) return;
    final found = _mapData.findZone(zoneId);
    if (found == null) return;

    // Find a matching uncompleted objective by zone tag.
    String? objId;
    for (final tag in found.zone.tags) {
      final match = gameState.objectives.where((o) =>
        !o.isCompleted && (
          o.params['itemId'] == tag ||
          o.params['targetTileTag'] == tag ||
          o.id == tag
        )
      ).firstOrNull;
      if (match != null) { objId = match.id; break; }
    }

    // Block random loot in zones without the "item" tag.
    if (objId == null && !found.zone.tags.contains('item')) return;

    onSearch(playerId, objId);
  }

  // ---- Input ----

  void _onPlayerTapped(String playerId) {
    if (gameState.phase != GamePhase.playerTurn) return;
    if (playerId != gameState.activePlayerId) return;
    final player = gameState.players.firstWhere((p) => p.playerId == playerId);
    if (player.actionsRemaining <= 0) return;

    if (_selectedPlayerId == playerId) { _clearSelection(); return; }

    _selectedPlayerId = playerId;
    _selectedZoneId   = player.zoneId;
    _actionMode = ActionMode.none;
    _reachableZoneIds  = _computeReachable(_selectedZoneId);
    _attackableZoneIds = _computeAttackable(_selectedZoneId);
    _doorZoneIds       = _computeDoorZones(_selectedZoneId);
    _updateOverlays();
    // Notify HUD so it rebuilds the PORTA button based on hasDoorAdjacent.
    onActionModeChanged(ActionMode.none);
  }

  void _onZoneTapped(String zoneId) {
    if (zoneId.isEmpty) return;
    if (_selectedPlayerId == null) return;
    if (gameState.phase != GamePhase.playerTurn) return;

    switch (_actionMode) {
      case ActionMode.move:
        if (_reachableZoneIds.contains(zoneId)) {
          onMoveToZone(_selectedPlayerId!, zoneId);
          // Exit move mode — movement is one activation per turn.
          _actionMode = ActionMode.none;
          onActionModeChanged(ActionMode.none);
        }

      case ActionMode.attack:
        if (_attackableZoneIds.contains(zoneId)) {
          final player   = gameState.players.firstWhere((p) => p.playerId == _selectedPlayerId);
          final weaponId = activeWeaponId ?? player.equippedLeft ?? player.equippedRight ?? 'fists';
          onAttackZone(_selectedPlayerId!, weaponId, zoneId);
          _clearSelection();
        }

      case ActionMode.openDoor:
        // Tapped zone must be adjacent with a closed door.
        if (_selectedZoneId != null && _doorZoneIds.contains(zoneId)) {
          onOpenDoor(_selectedPlayerId!, _selectedZoneId!, zoneId);
          _clearSelection();
        }

      case ActionMode.none:
        break; // movement requires pressing MOVER first
    }
  }

  void _onMapTapped(String tileId, double localX, double localY) {
    // Find which zone was tapped within this tile
    final tile = _mapData.tileById(tileId);
    if (tile == null) return;
    final r = _mapData.tileWorldRect(tile);

    final normX = localX / r.w;
    final normY = localY / r.h;

    for (final zone in tile.zones) {
      if (normX >= zone.rect.x && normX <= zone.rect.x + zone.rect.w &&
          normY >= zone.rect.y && normY <= zone.rect.y + zone.rect.h) {
        _onZoneTapped(zone.id);
        return;
      }
    }
  }

  // ---- Zone graph BFS ----

  Set<String> _computeReachable(String? fromZoneId) {
    if (fromZoneId == null) return {};
    final player = gameState.players.firstWhere((p) => p.playerId == _selectedPlayerId!);

    final maxZones    = SkillSystem.movementRange(player);
    final stepsLeft   = maxZones - player.zonesMovedThisTurn;
    if (player.actionsRemaining <= 0 || stepsLeft <= 0) return {};

    // BFS up to stepsLeft zones deep — but each step costs 1 action,
    // so also cap by actionsRemaining.
    final steps     = stepsLeft.clamp(0, player.actionsRemaining);
    final openDoors = gameState.openDoors;
    final reachable = <String>{};
    final frontier  = <String>{fromZoneId};

    for (var depth = 0; depth < steps; depth++) {
      final next = <String>{};
      for (final zoneId in frontier) {
        for (final adj in _mapData.adjacentZones(zoneId, openDoorKeys: openDoors)) {
          final id = adj.zone.id;
          if (id != fromZoneId && !reachable.contains(id)) {
            next.add(id);
          }
        }
      }
      reachable.addAll(next);
      frontier
        ..clear()
        ..addAll(next);
    }

    return reachable;
  }

  Set<String> _computeAttackable(String? fromZoneId) {
    if (fromZoneId == null) return {};
    final result = <String>{fromZoneId};
    for (final adj in _mapData.adjacentZones(fromZoneId, openDoorKeys: gameState.openDoors)) {
      result.add(adj.zone.id);
    }
    return result;
  }

  Set<String> _computeDoorZones(String? fromZoneId) {
    if (fromZoneId == null) return {};
    return _mapData
        .closedDoorsAdjacentTo(fromZoneId, gameState.openDoors)
        .toSet();
  }

  // ---- Overlays ----

  void _updateOverlays() {
    for (final entry in _zoneOverlays.entries) {
      ZoneHighlight h = ZoneHighlight.none;
      switch (_actionMode) {
        case ActionMode.move:
          if (_reachableZoneIds.contains(entry.key))  h = ZoneHighlight.reachable;
        case ActionMode.attack:
          if (_attackableZoneIds.contains(entry.key)) h = ZoneHighlight.attack;
        case ActionMode.openDoor:
          if (_doorZoneIds.contains(entry.key)) h = ZoneHighlight.door;
        case ActionMode.none:
          // No movement highlight — player must press MOVER first.
          // Only show door zones subtly when player is selected.
          if (_selectedPlayerId != null && _doorZoneIds.contains(entry.key)) {
            h = ZoneHighlight.doorClosed;
          }
      }
      if (entry.key == _selectedZoneId && _selectedPlayerId != null) {
        h = ZoneHighlight.selected;
      }
      entry.value.setHighlight(h);
    }
  }

  void _clearSelection() {
    _selectedPlayerId  = null;
    _selectedZoneId    = null;
    _actionMode        = ActionMode.none;
    _reachableZoneIds  = {};
    _attackableZoneIds = {};
    _doorZoneIds       = {};
    _updateOverlays();
    onActionModeChanged(ActionMode.none);
  }

  // ---- Camera ----

  void _centerCamera() {
    if (_mapData.tiles.isEmpty) return;
    final s = _mapData.tilePixelSize.toDouble();

    // Map bounds in world pixels.
    final minX = _mapData.tiles.map((t) => t.gridX).reduce((a, b) => a < b ? a : b) * s;
    final maxX = (_mapData.tiles.map((t) => t.gridX).reduce((a, b) => a > b ? a : b) + 1) * s;
    final minY = _mapData.tiles.map((t) => t.gridY).reduce((a, b) => a < b ? a : b) * s;
    final maxY = (_mapData.tiles.map((t) => t.gridY).reduce((a, b) => a > b ? a : b) + 1) * s;
    final mapCenter = Vector2((minX + maxX) / 2, (minY + maxY) / 2);

    // Prefer centering on the first alive player's zone, fall back to map center.
    final alive = gameState.players.where((p) => !p.isEliminated).toList();
    Vector2? playerPos;
    if (alive.isNotEmpty && alive.first.zoneId.isNotEmpty) {
      final p = worldPosForZone(alive.first.zoneId);
      if (p != Vector2.zero()) playerPos = p;
    }
    _cam.viewfinder.position = playerPos ?? mapCenter;
    _cam.viewfinder.zoom = _zoom;
  }

  @override
  void onScaleStart(ScaleStartInfo info) => _panStart = info.eventPosition.global;

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    final delta = info.eventPosition.global - _panStart;
    _cam.viewfinder.position -= delta / _zoom;
    _panStart = info.eventPosition.global;
    if (info.scale.global.x != 1.0) {
      _applyZoom(_zoom * info.scale.global.x);
    }
  }

  @override
  Color backgroundColor() => const Color(0xFF050510);
}

// ---- Movement trail component ----

class _MovementTrailComponent extends Component {
  final Vector2 from;
  final Vector2 to;
  double _alpha = 0.0;

  _MovementTrailComponent({required this.from, required this.to});

  @override
  void update(double dt) {
    _alpha = (_alpha + dt * 3).clamp(0.0, 1.0);
  }

  @override
  void render(Canvas canvas) {
    final opacity = _alpha;

    // Dashed line from → to
    final paint = Paint()
      ..color = const Color(0xFFFF8800).withValues(alpha: 0.7 * opacity)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final dir    = (to - from);
    final length = dir.length;
    if (length < 1) return;
    final unit   = dir / length;

    const dashLen = 18.0;
    const gapLen  = 10.0;
    var drawn = 0.0;
    var drawing = true;

    final path = Path();
    path.moveTo(from.x, from.y);
    var cur = from.clone();
    while (drawn < length) {
      final segLen = drawing
          ? math.min(dashLen, length - drawn)
          : math.min(gapLen,  length - drawn);
      cur = cur + unit * segLen;
      if (drawing) {
        path.lineTo(cur.x, cur.y);
      } else {
        path.moveTo(cur.x, cur.y);
      }
      drawn += segLen;
      drawing = !drawing;
    }
    canvas.drawPath(path, paint);

    // Arrowhead at destination
    if (length > 10) {
      final angle = math.atan2(dir.y, dir.x);
      const arrowLen = 20.0;
      const arrowAngle = 0.45;

      final arrowPaint = Paint()
        ..color = const Color(0xFFFF8800).withValues(alpha: opacity)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(to.x, to.y),
        Offset(to.x - arrowLen * math.cos(angle - arrowAngle),
               to.y - arrowLen * math.sin(angle - arrowAngle)),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(to.x, to.y),
        Offset(to.x - arrowLen * math.cos(angle + arrowAngle),
               to.y - arrowLen * math.sin(angle + arrowAngle)),
        arrowPaint,
      );
    }

    // Pulsing circle at destination
    final circlePaint = Paint()
      ..color = const Color(0xFFFF8800).withValues(alpha: 0.35 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(to.x, to.y), 28, circlePaint);
    canvas.drawCircle(Offset(to.x, to.y), 28,
        Paint()
          ..color = const Color(0xFFFF8800).withValues(alpha: 0.8 * opacity)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }
}
