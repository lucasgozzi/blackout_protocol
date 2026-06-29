import '../core/models/enemy.dart';
import 'asset_loader.dart';

const _enemiesPath = 'assets/data/enemies/enemies.json';

class EnemyCatalog {
  final Map<String, EnemyDefinition> _definitions;

  EnemyCatalog._(this._definitions);

  static Future<EnemyCatalog> load(AssetLoader loader) async {
    final json = await loader.loadJson(_enemiesPath);
    final list = (json['enemies'] as List)
        .map((e) => EnemyDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
    return EnemyCatalog._({for (final e in list) e.id: e});
  }

  EnemyDefinition getById(String id) {
    final def = _definitions[id];
    if (def == null) throw ArgumentError('Unknown enemy id: $id');
    return def;
  }

  List<EnemyDefinition> getAll() => _definitions.values.toList();

  List<EnemyDefinition> getByType(EnemyType type) =>
      _definitions.values.where((e) => e.type == type).toList();
}
