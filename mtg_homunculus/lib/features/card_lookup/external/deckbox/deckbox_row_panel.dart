import 'dart:convert';

/// A row's **edit panel** — the site's *Edit this row*, read so a row can be
/// saved back through `update_single` (mirror_editing.md).
///
/// **A save writes the whole row**: every field goes out each time. So what
/// the app does not change — other flags (signed, altered…), tags, price, the
/// counts — is sent back exactly as the panel held it. The panel is also
/// where Deckbox's own ids live: the card's, and each printing's edition id.
///
/// The selected values are read from each dropdown's `initial: [...]`, not
/// from its hidden input: the site's scripts fill the inputs from those on
/// load, and a multi-select's input is empty in the HTML.
class DeckboxRowPanel {
  const DeckboxRowPanel({
    required this.rowId,
    required this.cardId,
    required this.setId,
    required this.count,
    required this.tradeCount,
    required this.editionId,
    required this.conditionId,
    required this.languageId,
    required this.flags,
    required this.tagIds,
    required this.price,
    required this.editions,
  });

  /// `data-card-set-id` — the row's id, as on a list page.
  final String rowId;

  /// `data-card-id` — Deckbox's id for the card (not the printing).
  final String cardId;

  /// `data-set-id` — the list it is saved through: the Inventory's, even when
  /// opened from its Tradelist.
  final int setId;

  final String count;

  /// Null where the panel has no trade count (a Wishlist).
  final String? tradeCount;

  final int editionId;

  /// 0 none, 1 Mint, 2 Near Mint, 3 Good (Lightly Played), 4 Played,
  /// 5 Heavily Played, 6 Poor, 7 Proxy.
  final int conditionId;

  /// 0 none, 1 English, 2 German, 3 French, 4 Italian, 5 Spanish,
  /// 6 Portuguese, 7 Japanese, 8 Chinese, 9 Russian, 10 Korean,
  /// 11 Traditional Chinese.
  final int languageId;

  /// `is_foil`, `is_signed`, `is_proof`, `is_altered`, `is_misprint`, …
  final List<String> flags;

  /// Comma-joined, as the site sends them; null where the panel has no tags.
  final String? tagIds;

  /// A premium field; null when the panel has none, and then not sent.
  final String? price;

  /// The card's printings, as the edition dropdown lists them — first
  /// *[Unspecified Edition]*, id 0.
  final List<DeckboxEdition> editions;

  DeckboxEdition? get edition => editions.where((e) => e.id == editionId).firstOrNull;

  bool get foil => flags.contains('is_foil');

  /// The `data` parameter of `update_single`: this row as the panel holds it,
  /// with only the given fields changed.
  String saveData({int? editionId, int? conditionId, int? languageId, List<String>? flags}) => jsonEncode({
        'id': rowId,
        'card_id': cardId,
        'count': count,
        'trade_count': ?tradeCount,
        'price': ?price,
        'details': {
          'card_edition_id': '${editionId ?? this.editionId}',
          'condition_id': '${conditionId ?? this.conditionId}',
          'language_id': '${languageId ?? this.languageId}',
          'flags': (flags ?? this.flags).join(','),
        },
        'tag_ids': ?tagIds,
      });

  /// Reads the panel's HTML. Throws [FormatException] when a field the save
  /// needs is missing — a panel half-read must never be saved back.
  static DeckboxRowPanel parse(String html) {
    String attr(String name) {
      final m = RegExp('$name="([^"]*)"').firstMatch(html);
      if (m == null) throw FormatException('no $name in the panel');
      return m.group(1)!;
    }

    String? inputValue(String id) {
      final tag = RegExp('<input[^>]*id="$id"[^>]*>').firstMatch(html)?.group(0);
      if (tag == null) return null;
      return RegExp(r'value="([^"]*)"').firstMatch(tag)?.group(1) ?? '';
    }

    final count = inputValue('_pes_count');
    if (count == null) throw const FormatException('no count in the panel');

    List<String>? initial(String anchor) {
      final at = html.indexOf(anchor);
      if (at < 0) return null;
      final m = RegExp(r'initial:\s*\[([^\]]*)\]').firstMatch(html.substring(at));
      if (m == null) return null;
      return [
        for (final v in m.group(1)!.split(','))
          if (v.trim().replaceAll(RegExp('''^["']|["']\$'''), '') case final s when s.isNotEmpty) s,
      ];
    }

    int one(String field) {
      final values = initial("name: 'details[0][$field]'");
      final v = values == null || values.isEmpty ? null : int.tryParse(values.first);
      if (v == null) throw FormatException('no $field in the panel');
      return v;
    }

    final flags = initial("name: 'details[0][flags]'");
    if (flags == null) throw const FormatException('no flags in the panel');
    final tags = initial("id: '_pes_tag_ids'");

    return DeckboxRowPanel(
      rowId: attr('data-card-set-id'),
      cardId: attr('data-card-id'),
      setId: int.parse(attr('data-set-id')),
      count: count,
      tradeCount: inputValue('_pes_trade_count'),
      editionId: one('card_edition_id'),
      conditionId: one('condition_id'),
      languageId: one('language_id'),
      flags: flags,
      tagIds: tags?.join(','),
      price: inputValue('_pes_price'),
      editions: _editions(html),
    );
  }

  /// The edition dropdown's values — a JSON array literal in the panel's
  /// script: `[[html, id, …], …]`.
  static List<DeckboxEdition> _editions(String html) {
    const anchor = "Dropdown.all['details[0][card_edition_id]'] = new Dropdown(";
    final at = html.indexOf(anchor);
    if (at < 0) throw const FormatException('no edition list in the panel');
    final literal = _arrayAt(html, at + anchor.length);
    final values = jsonDecode(literal) as List;
    final named = RegExp(r"mtg_edition_name'>(.*?)<code>\((.*) #(.*)\)</code>");
    return [
      for (final v in values.cast<List>())
        if (named.firstMatch(v[0] as String) case final m?)
          DeckboxEdition(id: v[1] as int, name: _text(m.group(1)!), code: m.group(2)!, number: m.group(3)!)
        else
          DeckboxEdition(id: v[1] as int, name: '', code: '', number: ''),
    ];
  }

  /// The JSON array starting at [start] — brackets counted outside strings.
  static String _arrayAt(String s, int start) {
    var depth = 0;
    var inString = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '[') {
        depth++;
      } else if (c == ']' && --depth == 0) {
        return s.substring(start, i + 1);
      }
    }
    throw const FormatException('the edition list never closes');
  }

  static String _text(String html) => html
      .replaceAll(RegExp('<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .trim();
}

/// One printing in a row's edition dropdown — *Strixhaven: School of Mages
/// (STX #7)*. [code] is Deckbox's own (`PP_STX`, `PTC_27`), not Scryfall's.
class DeckboxEdition {
  const DeckboxEdition({required this.id, required this.name, required this.code, required this.number});

  final int id;

  /// Empty for *[Unspecified Edition]* (id 0).
  final String name;
  final String code;
  final String number;

  @override
  String toString() => id == 0 ? '[Unspecified Edition]' : '$name ($code #$number)';
}
