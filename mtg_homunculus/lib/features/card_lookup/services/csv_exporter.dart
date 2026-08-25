import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/collection_database.dart';

/// Exports a list as an RFC 4180–compliant CSV file and shares it via the
/// platform share sheet.
///
/// Columns (in order):
///   Name, Set Code, Collector Number, Finish, Language, Condition, Quantity
///
/// **Prices and set names are gone**, and deliberately. Both used to come from a
/// live Scryfall response held in memory; the local store keeps neither — prices
/// change daily and were dropped from the schema on purpose, and an entry's
/// snapshot carries the set *code* because that is what identifies a printing.
///
/// RFC 4180 rules applied:
///   - Lines separated by CRLF.
///   - Fields containing a comma, double-quote, CR, or LF are enclosed in
///     double-quotes.
///   - A double-quote inside a quoted field is escaped as two double-quotes.
///   - All other fields are written as-is (no unnecessary quoting).
class CsvExporter {
  CsvExporter._();

  static const _headers = [
    'Name',
    'Set Code',
    'Collector Number',
    'Finish',
    'Language',
    'Condition',
    'Quantity',
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Build the CSV string for [entries].
  ///
  /// Reads the denormalised snapshot rather than joining against `cards.db`, so
  /// an export still works with the card cache absent — which is the reason the
  /// snapshot exists.
  static String buildCsv(List<Entry> entries) {
    final rows = <String>[
      _row(_headers),
      for (final e in entries)
        _row([
          e.snapName,
          e.snapSetCode.toUpperCase(),
          e.snapCollector,
          Finish.label(e.finish),
          e.language,
          Condition.label(e.condition),
          e.quantity.toString(),
        ]),
    ];
    // RFC 4180 §2 — records separated by CRLF.
    return rows.join('\r\n');
  }

  /// Write a list to a temp CSV file and open the platform share sheet.
  static Future<void> share({
    required String name,
    required List<Entry> entries,
  }) async {
    final csv  = buildCsv(entries);
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(name)}.csv');
    await file.writeAsString(csv, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: '$name — Card Listing',
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Serialise one CSV row.
  static String _row(List<String> fields) => fields.map(_quote).join(',');

  /// Apply RFC 4180 quoting to a single field value.
  static String _quote(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\r') ||
        field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Sanitise the listing name for use as a filename.
  ///
  /// Removes characters that are not word characters, spaces, or hyphens;
  /// collapses whitespace to underscores; falls back to "listing" if blank.
  static String _safeName(String name) {
    final safe = name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final truncated = safe.isEmpty ? 'listing' : safe;
    return truncated.length > 50 ? truncated.substring(0, 50) : truncated;
  }
}
