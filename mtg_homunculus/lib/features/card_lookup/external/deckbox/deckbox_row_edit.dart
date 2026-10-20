import 'deckbox_mapping.dart';
import 'deckbox_row_panel.dart';

/// A mirrored row's fields as the export has them — what an edit is checked
/// against, and what it leaves behind.
typedef RowRaw = ({
  String printingId,
  String condition,
  String language,
  String foil,
  String rowFlags,
  int count,
  int? tradeCount,
});

/// What an edit changes, in the app's terms (mirror_editing.md). A field left
/// null is not changed — and is sent back exactly as Deckbox has it.
class RowEdit {
  const RowEdit({this.foil, this.language, this.condition, this.edition, this.cardId});

  final bool? foil;

  /// `(code: null)` is *any language* — a Wishlist's, or a generic row's.
  final ({String? code})? language;

  /// The app's 0–4; `(code: null)` is *any condition*.
  final ({int? code})? condition;

  /// A printing from **the row's own panel** — anything else Deckbox quietly
  /// turns into *[Unspecified Edition]* (E7). Id 0 is *any printing*.
  final DeckboxEdition? edition;

  /// The Scryfall printing [edition] was matched to, for the mirror; null
  /// when it matched none, or for *any printing*.
  final String? cardId;

  bool get isEmpty => foil == null && language == null && condition == null && edition == null;
}

/// Deckbox's own ids for a row's fields, and an edit worked out against a
/// row's panel — **pure**: no requests, no database.
///
/// The ids are the panel's dropdowns (E1, E8). The names are what the export
/// calls the same values, so a panel and a mirror row compare raw to raw.
class DeckboxRowEdit {
  DeckboxRowEdit._();

  /// Condition id → the export's name. 0, none, is the empty string.
  static const conditionNames = {
    1: 'Mint',
    2: 'Near Mint',
    3: 'Good (Lightly Played)',
    4: 'Played',
    5: 'Heavily Played',
    6: 'Poor',
    7: 'Proxy',
  };

  /// The app's condition (0–4) → Deckbox's id. **Mint is never chosen**: the
  /// app shows it as NM, and an NM row left alone is sent back as it was.
  static const conditionIds = {0: 2, 1: 3, 2: 4, 3: 5, 4: 6};

  /// Language id → the export's name.
  static const languageNames = {
    1: 'English',
    2: 'German',
    3: 'French',
    4: 'Italian',
    5: 'Spanish',
    6: 'Portuguese',
    7: 'Japanese',
    8: 'Chinese',
    9: 'Russian',
    10: 'Korean',
    11: 'Traditional Chinese',
  };

  /// A panel flag → the export's column, for the ones the app does not edit.
  static const flagColumns = {
    'is_signed': 'Signed',
    'is_proof': 'Artist Proof',
    'is_altered': 'Altered Art',
    'is_misprint': 'Misprint',
    'is_promo': 'Promo',
    'is_textless': 'Textless',
  };

  static int _languageId(String? code) {
    if (code == null) return 0;
    final name = DeckboxMapping.languages.entries.where((e) => e.value == code).firstOrNull?.key;
    final id = languageNames.entries.where((e) => e.value == name).firstOrNull?.key;
    if (id == null) throw ArgumentError('Deckbox has no language "$code"');
    return id;
  }

  /// The panel's fields as the export would show them.
  static RowRaw rawOf(DeckboxRowPanel p) => (
        printingId: p.editionId == 0 ? '' : '${p.editionId}',
        condition: conditionNames[p.conditionId] ?? '',
        language: languageNames[p.languageId] ?? '',
        foil: p.foil ? 'foil' : '',
        // As the mirror keeps them: the export's columns, in its order.
        rowFlags: [
          for (final column in DeckboxMapping.flagColumns)
            if (flagColumns.entries.any((e) => e.value == column && p.flags.contains(e.key))) column,
        ].join(','),
        count: int.tryParse(p.count) ?? -1,
        tradeCount: p.tradeCount == null ? null : int.tryParse(p.tradeCount!) ?? -1,
      );

  /// Why [panel] is not the row [row] — or null when it is. Compared raw, so a
  /// Mint row matches its mirror row however the app shows it. [counts] off
  /// skips the counts: after a merge they are the two rows' sum (E4).
  static String? mismatch(DeckboxRowPanel panel, RowRaw row, {bool counts = true}) {
    final p = rawOf(panel);
    String? differs(String what, Object? a, Object? b) => a == b ? null : '$what: Deckbox has "$a", expected "$b"';
    return differs('printing', p.printingId, row.printingId) ??
        differs('condition', p.condition, row.condition) ??
        differs('language', p.language, row.language) ??
        differs('foil', p.foil, row.foil) ??
        differs('flags', p.rowFlags, row.rowFlags) ??
        (counts ? differs('count', p.count, row.count) : null) ??
        (counts && row.tradeCount != null ? differs('count for trade', p.tradeCount, row.tradeCount) : null);
  }

  /// The `update_single` data: the row as [panel] holds it, with [edit]'s
  /// fields changed. Foil is toggled within the panel's flags, so signed,
  /// altered and the rest go back as they were.
  static String saveData(DeckboxRowPanel panel, RowEdit edit) {
    final foil = edit.foil;
    return panel.saveData(
      editionId: edit.edition?.id,
      conditionId: switch (edit.condition) {
        null => null,
        (code: null) => 0,
        (code: final int c) => conditionIds[c] ?? (throw ArgumentError('no Deckbox condition for $c')),
      },
      languageId: edit.language == null ? null : _languageId(edit.language!.code),
      flags: foil == null
          ? null
          : [
              for (final f in panel.flags)
                if (f != 'is_foil') f,
              if (foil) 'is_foil',
            ],
    );
  }

  /// The row as it should read once [edit] is saved — what the panel, opened
  /// again, must show (counts aside), and what the mirror row becomes.
  static RowRaw after(DeckboxRowPanel panel, RowEdit edit) {
    final before = rawOf(panel);
    return (
      printingId: switch (edit.edition) {
        null => before.printingId,
        DeckboxEdition(id: 0) => '',
        final e => '${e.id}',
      },
      condition: switch (edit.condition) {
        null => before.condition,
        (code: null) => '',
        (code: final int c) => conditionNames[conditionIds[c]]!,
      },
      language: edit.language == null ? before.language : languageNames[_languageId(edit.language!.code)] ?? '',
      foil: edit.foil == null ? before.foil : (edit.foil! ? 'foil' : ''),
      rowFlags: before.rowFlags,
      count: before.count,
      tradeCount: before.tradeCount,
    );
  }

  /// Each of the app's printings of a card → the panel edition it is, for
  /// **Change Version**: only what both know is offered.
  ///
  /// Deckbox's codes are mostly Scryfall's (`M14`, `MSH`) but not always
  /// (`1E` for `lea`), and old sets are numbered differently. So, in order:
  /// the same code and number; the same set name and number; the same set
  /// name, when that set holds exactly one printing on each side. Etched
  /// editions (`CMR_E`) are left out — etched is not offered in an edit.
  static Map<String, DeckboxEdition> matchPrintings(
    List<DeckboxEdition> editions,
    List<({String id, String setCode, String setName, String number})> printings,
  ) {
    final open = [
      for (final e in editions)
        if (e.id != 0 && !e.code.toUpperCase().endsWith('_E')) e,
    ];
    final matched = <String, DeckboxEdition>{};
    void pass(bool Function(DeckboxEdition e, ({String id, String setCode, String setName, String number}) p) same) {
      for (final p in printings) {
        if (matched.containsKey(p.id)) continue;
        final hit = open.where((e) => same(e, p)).toList();
        if (hit.length != 1) continue;
        matched[p.id] = hit.single;
        open.remove(hit.single);
      }
    }

    pass((e, p) => e.code.toLowerCase() == p.setCode.toLowerCase() && e.number == p.number);
    pass((e, p) => e.name == p.setName && e.number == p.number);
    pass((e, p) =>
        e.name == p.setName &&
        open.where((o) => o.name == e.name).length == 1 &&
        printings.where((q) => q.setName == p.setName && !matched.containsKey(q.id)).length == 1);
    return matched;
  }

  /// A row's identity once its fields change (`DeckboxMapping.identityOf`):
  /// the name and the six flag columns kept from [old] — the app edits none
  /// of them, and the flags' raw values are only in the identity.
  static String identityAfter(String old, RowRaw raw) {
    final parts = old.split('|');
    const tail = 6; // the flag columns
    final name = parts.sublist(0, parts.length - 4 - tail).join('|');
    return [name, raw.printingId, raw.condition, raw.language, raw.foil, ...parts.sublist(parts.length - tail)].join('|');
  }
}
