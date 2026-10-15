/// Deckbox's vocabulary, mapped to the app's — one export row at a time.
///
/// **Pure Dart**, like the client: no database, no Flutter. What it cannot
/// settle alone — an etched row's printing, which needs the card cache — it
/// hands back as a question ([DeckboxRow.etchedLookup]) for the caller.
///
/// Every mapping keeps Deckbox's **raw** value beside the app's. A row's
/// identity is its raw fields (D3), so an approximate mapping — *Mint* shown as
/// NM — changes only what is displayed, never which row a removal points at.
class DeckboxMapping {
  DeckboxMapping._();

  /// Finish values, as `Finish` in `collection_database.dart`. Repeated rather
  /// than imported so this file stays free of Flutter and drift.
  static const nonfoil = 1;
  static const foil = 2;
  static const etched = 4;

  /// Deckbox's conditions (its own filter menu, D7) → the app's 0–4.
  /// **Mint shows as NM**, the app's best; **Proxy has no app condition**.
  static const conditions = {
    'Mint': 0,
    'Near Mint': 0,
    'Good (Lightly Played)': 1,
    'Played': 2,
    'Heavily Played': 3,
    'Poor': 4,
  };

  /// The app's condition → what Deckbox's export and import call it. Mint and
  /// Proxy are never written.
  static const conditionNames = {
    0: 'Near Mint',
    1: 'Good (Lightly Played)',
    2: 'Played',
    3: 'Heavily Played',
    4: 'Poor',
  };

  /// Deckbox's eleven languages → the app's eleven codes, one to one (D7).
  static const languages = {
    'English': 'en',
    'German': 'de',
    'French': 'fr',
    'Italian': 'it',
    'Spanish': 'es',
    'Portuguese': 'pt',
    'Japanese': 'ja',
    'Chinese': 'zhs',
    'Russian': 'ru',
    'Korean': 'ko',
    'Traditional Chinese': 'zht',
  };

  /// The per-row flags the export carries, in its column order.
  static const flagColumns = [
    'Signed', 'Artist Proof', 'Altered Art', 'Misprint', 'Promo', 'Textless',
  ];

  /// What makes an export row a row on Deckbox — the identity a staged removal
  /// points at. The raw values, `|`-joined, in a fixed order.
  static String identityOf(Map<String, String> r) => [
        'Name', 'Printing Id', 'Condition', 'Language', 'Foil', ...flagColumns,
      ].map((k) => r[k] ?? '').join('|');

  /// One export row, read. Throws a [FormatException] for a row with no usable
  /// count — a malformed export is a loud failure, not a skipped row.
  static DeckboxRow read(Map<String, String> r, int position) {
    final count = int.tryParse(r['Count'] ?? '');
    if (count == null) {
      throw FormatException('row ${position + 1}: no count in "${r['Count']}"');
    }

    final printingId = r['Printing Id'] ?? '';
    final anyPrinting = printingId.isEmpty;
    final scryfall = r['Scryfall ID'] ?? '';
    final code = (r['Edition Code'] ?? '').toLowerCase();
    final foilRaw = r['Foil'] ?? '';
    final conditionRaw = r['Condition'] ?? '';
    final languageRaw = r['Language'] ?? '';

    // Etched is an edition on Deckbox: `<set>_e`, exported with no Scryfall id.
    final isEtched = !anyPrinting && code.endsWith('_e');
    final etchedSet = isEtched ? code.substring(0, code.length - 2) : null;

    return DeckboxRow(
      position: position,
      count: count,
      tradeCount: int.tryParse(r['Tradelist Count'] ?? '') ?? 0,
      printingId: printingId,
      condition: conditionRaw,
      language: languageRaw,
      foil: foilRaw,
      rowFlags: [
        for (final k in flagColumns)
          if ((r[k] ?? '').isNotEmpty) k,
      ].join(','),
      identityKey: identityOf(r),
      name: r['Name'] ?? '',
      edition: r['Edition'] ?? '',
      editionCode: code,
      cardNumber: r['Card Number'] ?? '',
      printingNote: r['Printing Note'] ?? '',
      lastUpdated: _parseUpdated(r['Last Updated']),
      anyPrinting: anyPrinting,
      // A generic row's Scryfall id is only a stand-in (D3): never its card.
      cardId: anyPrinting || scryfall.isEmpty ? null : scryfall,
      cardRef: scryfall.isEmpty ? null : scryfall,
      etchedLookup: etchedSet == null ? null : (set: etchedSet, number: r['Card Number'] ?? ''),
      // A generic row with no foil set says nothing about finish — not nonfoil.
      finish: isEtched
          ? etched
          : foilRaw == 'foil'
              ? foil
              : anyPrinting
                  ? null
                  : nonfoil,
      languageCode: languages[languageRaw],
      conditionCode: conditions[conditionRaw],
    );
  }

  /// `2026-10-14 13:21:49 UTC` → Unix seconds.
  static int? _parseUpdated(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final iso = raw.replaceFirst(' ', 'T').replaceFirst(' UTC', 'Z');
    final t = DateTime.tryParse(iso);
    return t == null ? null : t.millisecondsSinceEpoch ~/ 1000;
  }
}

/// One mirrored row, read from the export — raw fields and the app's mapping.
class DeckboxRow {
  const DeckboxRow({
    required this.position,
    required this.count,
    required this.tradeCount,
    required this.printingId,
    required this.condition,
    required this.language,
    required this.foil,
    required this.rowFlags,
    required this.identityKey,
    required this.name,
    required this.edition,
    required this.editionCode,
    required this.cardNumber,
    required this.printingNote,
    required this.lastUpdated,
    required this.anyPrinting,
    required this.cardId,
    required this.cardRef,
    required this.etchedLookup,
    required this.finish,
    required this.languageCode,
    required this.conditionCode,
  });

  final int position;
  final int count;
  final int tradeCount;
  final String printingId;
  final String condition;
  final String language;
  final String foil;
  final String rowFlags;
  final String identityKey;
  final String name;
  final String edition;
  final String editionCode;
  final String cardNumber;
  final String printingNote;
  final int? lastUpdated;
  final bool anyPrinting;
  final String? cardId;
  final String? cardRef;

  /// Set on an etched row: the base set and number to find its printing by,
  /// since the export gives it no Scryfall id.
  final ({String set, String number})? etchedLookup;

  final int? finish;
  final String? languageCode;
  final int? conditionCode;

  /// A copy with the printing an etched lookup found.
  DeckboxRow withCard(String id) => DeckboxRow(
        position: position,
        count: count,
        tradeCount: tradeCount,
        printingId: printingId,
        condition: condition,
        language: language,
        foil: foil,
        rowFlags: rowFlags,
        identityKey: identityKey,
        name: name,
        edition: edition,
        editionCode: editionCode,
        cardNumber: cardNumber,
        printingNote: printingNote,
        lastUpdated: lastUpdated,
        anyPrinting: anyPrinting,
        cardId: id,
        cardRef: id,
        etchedLookup: etchedLookup,
        finish: finish,
        languageCode: languageCode,
        conditionCode: conditionCode,
      );
}
