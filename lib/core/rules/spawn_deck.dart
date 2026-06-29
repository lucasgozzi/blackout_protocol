import 'dart:math';

enum SpawnCardType { walker, runner, heavy, abomination }

class SpawnCard {
  final SpawnCardType type;
  final int count;
  final String enemyId;

  const SpawnCard({required this.type, required this.count, required this.enemyId});
}

class SpawnDeck {
  final List<SpawnCard> _deck;
  final List<SpawnCard> _discard = [];
  final Random _rng;

  SpawnDeck._(this._deck, {Random? rng}) : _rng = rng ?? Random();

  /// Standard deck for campaign 01.
  factory SpawnDeck.campaign01({Random? rng}) {
    final cards = [
      // 10× Walker (drone_walker)
      for (var i = 0; i < 10; i++)
        const SpawnCard(type: SpawnCardType.walker, count: 2, enemyId: 'drone_walker'),
      // 6× Runner (drone_runner)
      for (var i = 0; i < 6; i++)
        const SpawnCard(type: SpawnCardType.runner, count: 1, enemyId: 'drone_runner'),
      // 6× Walker (infected_walker)
      for (var i = 0; i < 6; i++)
        const SpawnCard(type: SpawnCardType.walker, count: 2, enemyId: 'infected_walker'),
      // 4× Heavy (infected_heavy)
      for (var i = 0; i < 4; i++)
        const SpawnCard(type: SpawnCardType.heavy, count: 1, enemyId: 'infected_heavy'),
      // 4× Security Walker
      for (var i = 0; i < 4; i++)
        const SpawnCard(type: SpawnCardType.walker, count: 1, enemyId: 'security_walker'),
      // 2× Abomination (only drawn at high alert)
      for (var i = 0; i < 2; i++)
        const SpawnCard(type: SpawnCardType.abomination, count: 1, enemyId: 'security_abomination'),
    ]..shuffle(rng ?? Random());

    return SpawnDeck._(cards, rng: rng);
  }

  factory SpawnDeck.fromJson(Map<String, dynamic> json, {Random? rng}) {
    final cards = (json['cards'] as List).map((c) => SpawnCard(
      type: SpawnCardType.values.firstWhere(
          (t) => t.name == (c['type'] as String),
          orElse: () => SpawnCardType.walker),
      count: c['count'] as int,
      enemyId: c['enemyId'] as String,
    )).toList()..shuffle(rng ?? Random());
    return SpawnDeck._(cards, rng: rng);
  }

  /// Draw one card. When deck is empty, reshuffle discard into deck first.
  SpawnCard draw() {
    if (_deck.isEmpty) {
      _deck.addAll(_discard.reversed);
      _deck.shuffle(_rng);
      _discard.clear();
    }
    final card = _deck.removeAt(0);
    _discard.add(card);
    return card;
  }

  /// How many abomination cards remain in the deck.
  int get abominationsRemaining =>
      _deck.where((c) => c.type == SpawnCardType.abomination).length;

  int get deckSize    => _deck.length;
  int get discardSize => _discard.length;
}
