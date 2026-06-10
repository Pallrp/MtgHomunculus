import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/card_listing.dart';

/// Exports a [CardListing] as an RFC 4180–compliant CSV file and shares it
/// via the platform share sheet.
///
/// Columns (in order):
///   Name, Set Name, Set Code, Collector Number, Foil, Quantity,
///   Price USD, Price EUR
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
    'Set Name',
    'Set Code',
    'Collector Number',
    'Foil',
    'Quantity',
    'Price USD',
    'Price EUR',
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Build the CSV string for [listing].
  static String buildCsv(CardListing listing) {
    final rows = <String>[
      _row(_headers),
      for (final card in listing.cards)
        _row([
          card.printing.name,
          card.printing.setName,
          card.printing.setCode.toUpperCase(),
          card.printing.collectorNumber,
          card.isFoil ? 'TRUE' : 'FALSE',
          card.quantity.toString(),
          card.printing.priceUsd?.toStringAsFixed(2) ?? '',
          card.printing.priceEur?.toStringAsFixed(2) ?? '',
        ]),
    ];
    // RFC 4180 §2 — records separated by CRLF.
    return rows.join('\r\n');
  }

  /// Write [listing] to a temp CSV file and open the platform share sheet.
  static Future<void> share(CardListing listing) async {
    final csv  = buildCsv(listing);
    final dir  = await getTemporaryDirectory();
    final name = _safeName(listing.name);
    final file = File('${dir.path}/$name.csv');
    await file.writeAsString(csv, encoding: utf8);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: '${listing.name} — Card Listing',
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
