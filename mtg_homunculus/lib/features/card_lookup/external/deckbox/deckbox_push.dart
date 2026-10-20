import 'deckbox_mapping.dart';

/// The pure half of a push: writing staged additions as an import file, and
/// reading what Deckbox says back. **Pure Dart**, so every rule below is unit
/// tested rather than discovered on a real account.

/// One staged addition, as the push sees it.
typedef PendingAddition = ({
  int id,
  String name,
  String? cardId,
  bool anyPrinting,
  int? finish,
  String? languageCode,
  int? conditionCode,
  String setCode,
  String setName,
  String collectorNumber,
  int quantity,
  bool forTrade,
});

/// An import file's row, or why the addition cannot be one.
typedef ImportRow = ({Map<String, String>? fields, String? refusal});

class DeckboxImportFile {
  DeckboxImportFile._();

  /// The owner's own collection file's header, which Deckbox accepted whole
  /// (D4) — so a push writes exactly the format already proven.
  static const header = [
    'Count', 'Name', 'Edition Code', 'Edition', 'Card Number',
    'Condition', 'Foil', 'Language', 'My Price', 'Scryfall ID',
  ];

  /// Added to [header] when any addition in the push is up for trade: an
  /// Inventory import carries the trade count, and it **adds** (T4, T8). A
  /// file mixing flagged and unflagged rows is fine — `0` adds nothing (T9).
  static const tradeColumn = 'Tradelist Count';

  /// Deckbox's three etched editions (D6). Etched is an edition there, not a
  /// foil value — `etched` in the Foil column is refused (D4 p6).
  static const etchedEditions = {
    'mh2': (name: 'Modern Horizons 2 Etched', code: 'MH2_E'),
    'h1r': (name: 'Modern Horizons 1 Timeshifts Etched', code: 'H1R_E'),
    'sta': (name: 'Strixhaven Mystical Archive Etched', code: 'STA_E'),
  };

  /// How one staged addition is written, by D4 and D9:
  ///
  /// - **An ordinary printing goes by its Scryfall ID**, which Deckbox takes
  ///   over any edition name (D4 p3) and needs alone (p4). Name, edition and
  ///   number ride along for a person reading the file
  /// - **A generic row goes by name only** — never a Scryfall ID, or it lands
  ///   as that printing (D9 w5). Condition, language and foil only where set
  /// - **Etched** goes by Deckbox's etched edition, **without** a Scryfall ID —
  ///   the ID would win and land the plain printing (D4 p7)
  /// - **Secret Lair etched** has no edition to go to; it is written as `foil`,
  ///   by Scryfall ID (decided 2026-10-15)
  /// - **Any other etched** printing has nowhere on Deckbox — refused before
  ///   upload, named, left staged
  static ImportRow rowFor(PendingAddition a) {
    final language = _languageName(a.languageCode);
    final condition = a.conditionCode == null ? '' : DeckboxMapping.conditionNames[a.conditionCode] ?? '';

    final trade = a.forTrade ? '${a.quantity}' : '0';
    if (a.anyPrinting) {
      return (
        fields: {
          'Count': '${a.quantity}',
          'Name': a.name,
          'Condition': condition,
          'Foil': a.finish == DeckboxMapping.foil ? 'foil' : '',
          'Language': language,
          tradeColumn: trade,
        },
        refusal: null,
      );
    }

    final cardId = a.cardId;
    if (cardId == null) {
      return (fields: null, refusal: 'no printing to send — pick one first');
    }

    final set = a.setCode.toLowerCase();
    var foil = a.finish == DeckboxMapping.foil ? 'foil' : '';
    var edition = a.setName;
    var code = a.setCode.toUpperCase();
    var scryfall = cardId;

    if (a.finish == DeckboxMapping.etched) {
      final etched = etchedEditions[set];
      if (etched != null) {
        edition = etched.name;
        code = etched.code;
        scryfall = '';
      } else if (set == 'sld') {
        foil = 'foil';
      } else {
        return (fields: null, refusal: 'Deckbox has no etched edition for ${a.setCode.toUpperCase()}');
      }
    }

    return (
      fields: {
        'Count': '${a.quantity}',
        'Name': a.name,
        'Edition Code': code,
        'Edition': edition,
        'Card Number': a.collectorNumber,
        'Condition': condition.isEmpty ? 'Near Mint' : condition,
        'Foil': foil,
        'Language': language.isEmpty ? 'English' : language,
        'Scryfall ID': scryfall,
        tradeColumn: trade,
      },
      refusal: null,
    );
  }

  /// The file: [header], then one line per row, CRLF, RFC 4180 quoting.
  /// [withTrade] adds [tradeColumn] — only when some row is up for trade, so
  /// a push with none sends exactly the file it always has.
  static String write(Iterable<Map<String, String>> rows, {bool withTrade = false}) {
    final columns = [...header, if (withTrade) tradeColumn];
    return [
      columns.join(','),
      for (final r in rows) columns.map((h) => _quote(r[h] ?? '')).join(','),
    ].join('\r\n');
  }

  /// What Deckbox will echo back for a row it refuses — the columns its
  /// refusal table shows — so a refusal can be matched to what was sent.
  static String echoKey(Map<String, String> r) =>
      [r['Name'], r['Edition'], r['Condition'], r['Foil'], r['Language']]
          .map((v) => (v ?? '').trim())
          .join('|');

  static String _quote(String v) =>
      v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

  static String _languageName(String? code) {
    if (code == null) return '';
    for (final e in DeckboxMapping.languages.entries) {
      if (e.value == code) return e.key;
    }
    return '';
  }
}

// -----------------------------------------------------------------------------
// The import's reply
// -----------------------------------------------------------------------------

sealed class ImportReply {
  const ImportReply();

  /// Reads the JavaScript Deckbox sends back from an import (D4):
  ///
  /// - **Accepted:** the reply is the page's own reload, nothing more
  /// - **Refused:** it fills `file_check_results` with the rejected rows — and
  ///   the cell Deckbox objected to carries `class="error"`. Nothing from a
  ///   refused file lands
  /// - **Anything else** is a reply this client does not know
  static ImportReply read(String body) {
    if (body.contains("Element.update('file_check_results'")) {
      return ImportRefused(_echoRows(_unescapeJs(body)));
    }
    if (body.contains('window.location.reload()') && !body.contains('file_check_results')) {
      return const ImportAccepted();
    }
    return const ImportUnknown();
  }

  static String _unescapeJs(String s) => s
      .replaceAll(r'\"', '"')
      .replaceAll(r"\'", "'")
      .replaceAll(r'\/', '/')
      .replaceAll(r'\n', '\n');

  /// Only if a reply ever comes without its header row: the D4 file's order.
  static const _fallbackColumns = [
    'Count', 'Name', 'Edition', 'Card Number', 'Condition', 'Foil', 'Language', 'My Price',
  ];

  /// **The echo's columns are the uploaded file's**, in its order — named by
  /// the table's own `<th>` row (T6, 2026-10-19: a file of *Count, Name,
  /// Condition, Language, Foil, Scryfall ID, Tradelist Count* echoed as those,
  /// *Scryfall ID* dropped). Reading them by a fixed order mislabelled every
  /// column after *Name* for any file but D4's.
  static List<EchoedRow> _echoRows(String html) {
    final rows = <EchoedRow>[];
    var columns = _fallbackColumns;
    for (final tr in RegExp(r'<tr>(.*?)</tr>', dotAll: true).allMatches(html)) {
      final heads = [
        for (final h in RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true).allMatches(tr.group(1)!)) _text(h.group(1)!),
      ];
      if (heads.isNotEmpty) {
        columns = heads;
        continue;
      }
      final cells = RegExp(r'<td class="([^"]*)">(.*?)</td>', dotAll: true)
          .allMatches(tr.group(1)!)
          .toList();
      if (cells.isEmpty) continue;
      final values = <String, String>{};
      final errors = <String>{};
      for (var i = 0; i < cells.length && i < columns.length; i++) {
        values[columns[i]] = _text(cells[i].group(2)!);
        if (cells[i].group(1)!.contains('error')) errors.add(columns[i]);
      }
      rows.add(EchoedRow(values, errors));
    }
    return rows;
  }

  static String _text(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .trim();
}

final class ImportAccepted extends ImportReply {
  const ImportAccepted();
}

final class ImportRefused extends ImportReply {
  const ImportRefused(this.rows);
  final List<EchoedRow> rows;
}

final class ImportUnknown extends ImportReply {
  const ImportUnknown();
}

/// One row Deckbox refused, as it echoed it, and which of its columns it
/// marked as the problem.
class EchoedRow {
  const EchoedRow(this.values, this.errorColumns);

  final Map<String, String> values;
  final Set<String> errorColumns;

  String get echoKey => DeckboxImportFile.echoKey(values);

  /// *"Deckbox refused this row's edition"* — or just *"this row"* when it
  /// marked nothing.
  String get reason => errorColumns.isEmpty
      ? 'Deckbox refused this row'
      : "Deckbox refused this row's ${errorColumns.map((c) => c.toLowerCase()).join(' and ')}";
}
