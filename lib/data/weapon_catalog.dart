import '../core/models/weapon.dart';
import 'asset_loader.dart';

const _weaponsPath = 'assets/data/weapons/weapons.json';

class WeaponCatalog {
  final Map<String, WeaponDefinition> _definitions;

  WeaponCatalog._(this._definitions);
  // ignore: library_private_types_in_public_api
  WeaponCatalog.fromMap(Map<String, WeaponDefinition> map) : _definitions = map;

  static Future<WeaponCatalog> load(AssetLoader loader) async {
    final json = await loader.loadJson(_weaponsPath);
    final list = (json['weapons'] as List)
        .map((e) => WeaponDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
    return WeaponCatalog._({for (final w in list) w.id: w});
  }

  WeaponDefinition getById(String id) =>
      _definitions[id] ?? WeaponDefinition.fists;

  List<WeaponDefinition> getAll() => _definitions.values.toList();

  bool exists(String id) => _definitions.containsKey(id);
}
