import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'cards_database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// Bookkeeping — sync state and version stamps.
///
/// See [MetaKeys] for the keys this holds and what each one governs.
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Named explicitly: drift would otherwise generate a row class called `Set`,
/// which shadows `dart:core`'s `Set<T>` and breaks every `Set<Column>` in the
/// generated code.
@DataClassName('CardSet')
class Sets extends Table {
  /// Scryfall set code, lowercase: `xln`, `lci`.
  TextColumn get code => text()();
  TextColumn get name => text()();

  /// Unix seconds. Null when Scryfall has no release date.
  IntColumn get releasedAt => integer().nullable()();
  TextColumn get setType => text().nullable()();

  @override
  Set<Column> get primaryKey => {code};
}

/// One row per **printing**, keyed by Scryfall's own id.
///
/// Note the collector number is TEXT, not INTEGER: real numbers include `★`,
/// `123a`, and leading zeros that matter for matching what is printed.
class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get oracleId => text()();
  TextColumn get illustrationId => text().nullable()();

  TextColumn get name => text()();
  TextColumn get setCode => text().references(Sets, #code)();
  TextColumn get collectorNumber => text()();
  TextColumn get lang => text().withDefault(const Constant('en'))();
  IntColumn get rarity => integer().nullable()();
  IntColumn get releasedAt => integer().nullable()();

  // gameplay
  RealColumn get cmc => real().nullable()();
  TextColumn get colors => text().nullable()();
  TextColumn get colorIdentity => text().nullable()();
  TextColumn get watermark => text().nullable()();

  // presentation
  TextColumn get layout => text().nullable()();
  BoolColumn get fullArt => boolean().withDefault(const Constant(false))();
  BoolColumn get hasBack => boolean().withDefault(const Constant(false))();

  /// Unix seconds — the image cache-buster. Image URLs are derived, never stored.
  IntColumn get imageUpdatedAt => integer().nullable()();

  /// 0 missing · 1 placeholder · 2 lowres · 3 highres_scan.
  IntColumn get imageStatus => integer().withDefault(const Constant(0))();

  /// Bitmask: 1 nonfoil · 2 foil · 4 etched.
  IntColumn get finishes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Keys stored in [Meta].
abstract final class MetaKeys {
  /// Scryfall's ETag for the bulk file. **This** decides whether to re-download;
  /// [bulkUpdatedAt] is only for showing a human.
  static const bulkEtag = 'bulk_etag';
  static const bulkUpdatedAt = 'bulk_updated_at';
  static const bulkImportedAt = 'bulk_imported_at';
  static const bulkCardCount = 'bulk_card_count';
  static const lastUpdatePrompted = 'last_update_prompted';

  /// `DHash.version` of the fetched index. Tracks the hash grid, which changes on
  /// its own schedule and silently invalidates the index when it does — a grid
  /// change produces different hashes with no error, only matches that never
  /// happen. Unrelated to bulk versioning above.
  static const hashIndexVersion = 'hash_index_version';

  static const schemaVersion = 'schema_version';
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// Bulk card data from Scryfall. **Disposable** — re-downloadable, safe to wipe,
/// and excluded from Android auto-backup. Nothing the user created lives here;
/// that is `collection.db`.
@DriftDatabase(tables: [Meta, Sets, Cards])
class CardsDatabase extends _$CardsDatabase {
  CardsDatabase() : super(_open());
  CardsDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createNameIndex();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Name search index — a **standalone** FTS5 table over *unique names*, not an
  /// external-content table over [Cards].
  ///
  /// Indexing card rows would let reprints eat the result window: `Forest` has
  /// 948 printings, and a 50-row query over rows returns ~18 distinct names
  /// (measured 2026-08-25). Unique names return 50, which is what the
  /// edit-distance rerank needs to choose from.
  ///
  /// `tokenize='trigram'` is what makes garbled OCR matchable at all — it indexes
  /// every 3-character sequence, so a damaged name still shares most of them.
  /// Requires **SQLite 3.34+**; the bundled build is 3.53.4.
  ///
  /// No triggers, deliberately. They cost 5.7s against 0.9s for insert-then-rebuild
  /// on a 116k import (measured), and every write here comes from one importer.
  Future<void> _createNameIndex() async {
    await customStatement(
      // `norm` is what gets matched; `name` rides along UNINDEXED so a hit maps
      // straight back to the real name for the cards lookup. Both sides of the
      // comparison must be normalised the same way -- matching a normalised
      // query against raw names would lose every trigram touching punctuation.
      "CREATE VIRTUAL TABLE IF NOT EXISTS card_names_fts "
      "USING fts5(norm, name UNINDEXED, tokenize='trigram')",
    );
    // Name is how an FTS hit resolves back to printings, so it must be indexed.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_name ON cards(name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_setnum '
      'ON cards(set_code, collector_number)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_oracle ON cards(oracle_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cards_illus ON cards(illustration_id)',
    );
  }

  // ── meta ──────────────────────────────────────────────────────────────────

  Future<String?> metaValue(String key) async {
    final row = await (select(meta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) => into(meta).insertOnConflictUpdate(
        MetaData(key: key, value: value),
      );

  // ── name index ────────────────────────────────────────────────────────────

  /// Rebuild `card_names_fts` from the distinct names in [Cards].
  ///
  /// Use after a full import: 0.6s against the 5.3s that triggers would have added
  /// across 116k inserts.
  Future<void> rebuildNameIndex() async {
    await customStatement('DELETE FROM card_names_fts');
    await _indexNames(await _distinctNames());
  }

  /// Add any names not already indexed.
  ///
  /// For incremental sync: 700 new cards might add 400 names, and the rest are
  /// alternate printings of names already present.
  Future<void> addNewNames() async {
    final existing = {
      for (final r in await customSelect('SELECT name FROM card_names_fts').get())
        r.read<String>('name'),
    };
    final missing =
        (await _distinctNames()).where((n) => !existing.contains(n)).toList();
    if (missing.isNotEmpty) await _indexNames(missing);
  }

  Future<List<String>> _distinctNames() async {
    final rows =
        await customSelect('SELECT DISTINCT name FROM cards ORDER BY name').get();
    return [for (final r in rows) r.read<String>('name')];
  }

  /// Normalisation happens in Dart, not SQL, so the *same function* produces both
  /// the indexed form and the query form. SQL could lowercase but not strip
  /// punctuation, and two near-identical implementations is exactly the drift
  /// this avoids.
  Future<void> _indexNames(List<String> names) async {
    await batch((b) {
      for (final n in names) {
        b.customStatement(
          'INSERT INTO card_names_fts(norm, name) VALUES (?, ?)',
          [normaliseName(n), n],
        );
      }
    });
  }

  /// Candidate names for a (possibly garbled) OCR read.
  ///
  /// Decomposes [query] into trigrams and ORs them, so a damaged name still
  /// matches on the sequences that survived. A plain `MATCH 'colossai dreadmavv'`
  /// returns **nothing** — FTS5 requires every query trigram to be present, and
  /// the OR decomposition is the whole trick.
  ///
  /// Returns names ranked by trigram overlap. Callers rerank by edit distance:
  /// BM25 is order-blind and can rank a name sharing scattered trigrams above the
  /// true match.
  Future<List<String>> nameCandidates(String query, {int limit = 50}) async {
    final normalised = normaliseName(query);
    final trigrams = <String>{
      for (var i = 0; i + 3 <= normalised.length; i++)
        normalised.substring(i, i + 3),
    }.where((t) => !t.contains('"')).toList();

    if (trigrams.isEmpty) return const [];

    final expr = trigrams.map((t) => '"$t"').join(' OR ');
    final rows = await customSelect(
      'SELECT name FROM card_names_fts WHERE norm MATCH ? '
      'ORDER BY rank LIMIT ?',
      variables: [Variable<String>(expr), Variable<int>(limit)],
    ).get();
    return [for (final r in rows) r.read<String>('name')];
  }

  /// Lowercase, letters/digits/spaces only.
  ///
  /// ML Kit invents commas and apostrophes constantly and they carry no
  /// identifying information, so removing them before comparing deletes a class
  /// of mismatch for free. Names are stored normalised in the FTS table, so the
  /// same function must be used on both sides — see [_indexNames].
  static String normaliseName(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      if ((r >= 97 && r <= 122) || (r >= 48 && r <= 57)) {
        b.writeCharCode(r);
      } else if (r == 32 && b.isNotEmpty) {
        b.write(' ');
      }
    }
    return b.toString().trim();
  }
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'cards.db')),
      );
    });
