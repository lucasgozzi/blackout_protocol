import 'dart:math';

class LootItem {
  final String id;
  final String name;
  final String type;

  const LootItem({required this.id, required this.name, required this.type});

  bool get isNothing => type == 'none';
}

class SearchSystem {
  final List<_WeightedItem> _table;
  final Random _rng;

  SearchSystem._(this._table, {Random? rng}) : _rng = rng ?? Random();

  static SearchSystem fromJson(Map<String, dynamic> json, {Random? rng}) {
    final items = (json['items'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return _WeightedItem(
        item: LootItem(
          id: m['id'] as String,
          name: m['name'] as String,
          type: m['type'] as String,
        ),
        weight: m['weight'] as int,
      );
    }).toList();
    return SearchSystem._(items, rng: rng);
  }

  LootItem draw() {
    final total = _table.fold(0, (sum, e) => sum + e.weight);
    var roll = _rng.nextInt(total);
    for (final entry in _table) {
      roll -= entry.weight;
      if (roll < 0) return entry.item;
    }
    return _table.last.item;
  }
}

class _WeightedItem {
  final LootItem item;
  final int weight;
  const _WeightedItem({required this.item, required this.weight});
}
