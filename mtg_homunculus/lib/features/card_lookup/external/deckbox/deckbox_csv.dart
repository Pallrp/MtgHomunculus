/// Deckbox's CSV exports, read into rows keyed by column name.
///
/// **Pure Dart**, like the client. RFC 4180 as the exports use it: commas,
/// double-quoted fields where a value holds a comma (`"Edgar, Moonlit
/// Sovereign"`), doubled quotes inside quotes, CRLF or LF between records.
class DeckboxCsv {
  DeckboxCsv._();

  /// Each data row as `{column: value}`. Missing trailing cells read as empty.
  static List<Map<String, String>> rows(String text) {
    final records = parse(text);
    if (records.isEmpty) return const [];
    final header = records.first;
    return [
      for (final r in records.skip(1))
        if (r.length > 1 || (r.isNotEmpty && r.first.isNotEmpty))
          {
            for (var i = 0; i < header.length; i++)
              header[i]: i < r.length ? r[i] : '',
          },
    ];
  }

  static List<List<String>> parse(String text) {
    // A UTF-8 byte-order mark would otherwise glue itself to the first column.
    final src = text.startsWith('﻿') ? text.substring(1) : text;
    final records = <List<String>>[];
    var record = <String>[];
    final field = StringBuffer();
    var quoted = false;

    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < src.length && src[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        record.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
        record.add(field.toString());
        field.clear();
        records.add(record);
        record = <String>[];
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || record.isNotEmpty) {
      record.add(field.toString());
      records.add(record);
    }
    return records;
  }
}
