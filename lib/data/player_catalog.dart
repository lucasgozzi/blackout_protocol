import '../core/models/player.dart';
import 'asset_loader.dart';

const _playersPath = 'assets/data/players/players.json';

class PlayerCatalog {
  final Map<String, PlayerDefinition> _definitions;

  PlayerCatalog._(this._definitions);

  static Future<PlayerCatalog> load(AssetLoader loader) async {
    final json = await loader.loadJson(_playersPath);
    final list = (json['players'] as List)
        .map((e) => PlayerDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
    return PlayerCatalog._({for (final p in list) p.id: p});
  }

  PlayerDefinition getById(String id) {
    final def = _definitions[id];
    if (def == null) throw ArgumentError('Unknown player id: $id');
    return def;
  }

  List<PlayerDefinition> getAll() => _definitions.values.toList();
}
