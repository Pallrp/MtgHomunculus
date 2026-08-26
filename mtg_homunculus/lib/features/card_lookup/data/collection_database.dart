import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'collection_database.g.dart';

// ---------------------------------------------------------------------------
// Vocabulary
// ---------------------------------------------------------------------------

/// Card finish, as a bitmask value.
///
/// The same three flags `cards.finishes` uses, so a printing's available
/// finishes and an entry's chosen finish speak one language and an entry can be
/// validated against its printing without a lookup table.
abstract final class Finish {
  static const nonfoil = 1;
  static const foil = 2;
  static const etched = 4;

  static const all = [nonfoil, foil, etched];

  static String label(int v) => switch (v) {
        foil => 'Foil',
        etched => 'Etched',
        _ => 'Nonfoil',
      };
}

/// Sleeve condition, worst-to-best ordered so comparisons mean something.
abstract final class Condition {
  static const nearMint = 0;
  static const lightlyPlayed = 1;
  static const moderatelyPlayed = 2;
  static const heavilyPlayed = 3;
  static const damaged = 4;

  static const all = [
    nearMint,
    lightlyPlayed,
    moderatelyPlayed,
    heavilyPlayed,
    damaged,
  ];

  static String label(int v) => switch (v) {
        lightlyPlayed => 'LP',
        moderatelyPlayed => 'MP',
        heavilyPlayed => 'HP',
        damaged => 'DMG',
        _ => 'NM',
      };
}

/// App-wide defaults for the variant key.
///
/// A scan cannot see finish, language or condition, so every scanned entry is
/// created with these and corrected later if wrong. Kept beside the key itself
/// so "what a new entry looks like" is one place, not a constant repeated at
/// every call site.
abstract final class VariantDefaults {
  static const finish = Finish.nonfoil;
  static const language = 'en';
  static const condition = Condition.nearMint;
}

/// The printing a variant row points at, when it is not the card the editor was
/// opened on.
///
/// A variant can be changed to a different edition, at which point it stops
/// being a variant *of that card* and becomes an entry of another printing. The
/// snapshot travels with it because the entry it becomes needs one.
typedef VariantPrinting = ({
  String cardId,
  String name,
  String setCode,
  String setName,
  String collectorNumber,
});

/// One row of the variant editor — a variant the list should end up holding.
///
/// The editor opens showing the variants already in the list, so what it hands
/// back is the **desired final state**, not a list of changes. See
/// [CollectionDatabase.setVariantsFor].
class VariantEdit {
  final int finish;
  final String language;
  final int condition;

  /// Null means "the card the editor was opened on".
  ///
  /// Set when the user changed this row's edition. On save it leaves this
  /// card's variant set and is written under the printing it now names.
  final VariantPrinting? printing;

  /// Null means "leave whatever this variant already had".
  ///
  /// The distinction matters: the editor is about *which* variants exist, and
  /// opening it to add a foil must not silently reset the nonfoil row's count of
  /// four back to one.
  final int? quantity;

  const VariantEdit({
    this.finish = VariantDefaults.finish,
    this.language = VariantDefaults.language,
    this.condition = VariantDefaults.condition,
    this.quantity,
    this.printing,
  });

  VariantEdit copyWith({
    int? finish,
    String? language,
    int? condition,
    int? quantity,
    VariantPrinting? printing,
  }) =>
      VariantEdit(
        finish: finish ?? this.finish,
        language: language ?? this.language,
        condition: condition ?? this.condition,
        quantity: quantity ?? this.quantity,
        printing: printing ?? this.printing,
      );

  /// The variant an existing entry represents, for prepopulating the editor.
  ///
  /// Carries its printing, because the editor spans printings: two rows of the
  /// same card in different editions are both variants of it.
  factory VariantEdit.of(Entry e) => VariantEdit(
        finish: e.finish,
        language: e.language,
        condition: e.condition,
        quantity: e.quantity,
        printing: (
          cardId: e.cardId,
          name: e.snapName,
          setCode: e.snapSetCode,
          setName: e.snapSetName,
          collectorNumber: e.snapCollector,
        ),
      );
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// A named list of cards — the primary unit the user manages.
@DataClassName('CardList')
class Lists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// The always-present buffer list that replaces Quick Scan: scan into it,
  /// then cut or copy into a real list. Exactly one row carries this.
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

/// One variant of one printing, in one list.
///
/// [cardId] is a Scryfall id and a **logical** foreign key into `cards.db` — it
/// cannot be enforced, because the two live in separate files. That separation
/// is deliberate: a list has to survive the card cache being cleared, which is
/// also why [snapName] and friends exist.
class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get listId =>
      integer().references(Lists, #id, onDelete: KeyAction.cascade)();

  /// Scryfall printing id. Not `oracle_id`: an entry is about a specific
  /// printing, not a card.
  TextColumn get cardId => text()();

  // ── the variant key ──────────────────────────────────────────────────────
  // Changing this shape means a table rebuild (SQLite cannot ALTER a UNIQUE
  // constraint), so it is defined here and referenced by [variantKey] rather
  // than spelled out anywhere else.
  IntColumn get finish => integer()();
  TextColumn get language => text()();
  IntColumn get condition => integer()();

  /// Always at least 1 — see [customConstraints]. Zero means "remove the row",
  /// which [CollectionDatabase.setQuantity] does rather than storing it.
  IntColumn get quantity => integer()();

  /// Unix seconds. Powers the "Scanned" sort order.
  IntColumn get addedAt => integer()();

  // ── denormalised snapshot ────────────────────────────────────────────────
  // Enough to render a row with cards.db absent or wiped. Not a cache to keep
  // fresh: it is what the card was called when it was added.
  TextColumn get snapName => text()();
  TextColumn get snapSetCode => text()();

  /// The set's full name, stored rather than joined.
  ///
  /// It is display data with no identifying role — [snapSetCode] is what names
  /// the printing — so keeping it here rather than looking it up in `cards.db`
  /// is what lets an export and a row render with the card cache absent, which
  /// is the entire point of the snapshot. Stale if Scryfall ever renames a set,
  /// and that is correct: this records what the card was called when it was
  /// added, it is not a cache to keep fresh.
  TextColumn get snapSetName => text().withDefault(const Constant(''))();

  TextColumn get snapCollector => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {listId, cardId, finish, language, condition},
      ];

  /// Written as a table constraint rather than `quantity.check(...)`: the column
  /// form is drift's own idiom but reads as a getter returning itself, which the
  /// analyzer rejects.
  @override
  List<String> get customConstraints => ['CHECK (quantity > 0)'];
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// Lists and their entries. **Precious** — small, and the only file here that
/// cannot be rebuilt from the network.
///
/// Deliberately separate from `cards.db`, which is a disposable cache of
/// Scryfall's bulk data. Wiping that must never cost a user their collection.
@DriftDatabase(tables: [Lists, Entries])
class CollectionDatabase extends _$CollectionDatabase {
  CollectionDatabase() : super(_open());
  CollectionDatabase.forTesting(super.executor);

  static CollectionDatabase? _instance;

  /// The one instance the app uses.
  ///
  /// A singleton because drift propagates stream invalidation **within** an
  /// instance, not across them: a second connection to the same file would let
  /// the scanner add a card that the open sheet never hears about. Opening is
  /// lazy, so this costs nothing until the card lookup is entered.
  static CollectionDatabase get instance => _instance ??= CollectionDatabase();

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // Required for the entries -> lists cascade; SQLite defaults it off.
          await customStatement('PRAGMA foreign_keys = ON');
          await ensureDefaultList();
        },
      );

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  /// The buffer list, created if it does not exist yet.
  ///
  /// Runs on every open rather than on first launch only: "there is always
  /// somewhere to scan into" is an invariant, and a first-launch hook cannot
  /// restore it if the row is ever lost.
  Future<CardList> ensureDefaultList() async {
    final existing = await (select(lists)
          ..where((l) => l.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing;

    final now = _now();
    final id = await into(lists).insert(ListsCompanion.insert(
      name: 'Scanned',
      isDefault: const Value(true),
      createdAt: now,
      updatedAt: now,
    ));
    return (select(lists)..where((l) => l.id.equals(id))).getSingle();
  }

  Future<CardList> createList(String name, {String description = ''}) async {
    final now = _now();
    final id = await into(lists).insert(ListsCompanion.insert(
      name: name,
      description: Value(description),
      createdAt: now,
      updatedAt: now,
    ));
    return (select(lists)..where((l) => l.id.equals(id))).getSingle();
  }

  /// Newest activity first, but the default list always leads.
  ///
  /// It is where scanning lands, so it is the list the user most often wants and
  /// the one whose position should not move around under them.
  Future<List<CardList>> allLists() => (select(lists)
        ..orderBy([
          (l) => OrderingTerm.desc(l.isDefault),
          (l) => OrderingTerm.desc(l.updatedAt),
        ]))
      .get();

  Stream<List<CardList>> watchLists() => (select(lists)
        ..orderBy([
          (l) => OrderingTerm.desc(l.isDefault),
          (l) => OrderingTerm.desc(l.updatedAt),
        ]))
      .watch();

  Future<CardList?> listById(int id) =>
      (select(lists)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<void> renameList(int id, String name, {String? description}) =>
      (update(lists)..where((l) => l.id.equals(id))).write(ListsCompanion(
        name: Value(name),
        description: description == null ? const Value.absent() : Value(description),
        updatedAt: Value(_now()),
      ));

  /// Delete a list and, by cascade, its entries.
  ///
  /// Refuses the default list: it is the scan target, and the UI hides the
  /// action rather than relying on this — but a guard in the one place that
  /// actually deletes is worth more than a hidden button.
  Future<bool> deleteList(int id) async {
    final row = await listById(id);
    if (row == null || row.isDefault) return false;
    await (delete(lists)..where((l) => l.id.equals(id))).go();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Entries
  // ---------------------------------------------------------------------------

  /// Add one copy, or increment the matching variant if it is already there.
  ///
  /// The `UNIQUE` constraint on the variant key is what makes this safe: two
  /// scans of the same printing in the same finish, language and condition are
  /// the same row by definition, so this cannot create a near-duplicate the user
  /// then has to merge by hand.
  Future<int> addCard({
    required int listId,
    required String cardId,
    required String name,
    required String setCode,
    required String collectorNumber,
    String setName = '',
    int finish = VariantDefaults.finish,
    String language = VariantDefaults.language,
    int condition = VariantDefaults.condition,
    int quantity = 1,
  }) async {
    final existing = await (select(entries)
          ..where((e) =>
              e.listId.equals(listId) &
              e.cardId.equals(cardId) &
              e.finish.equals(finish) &
              e.language.equals(language) &
              e.condition.equals(condition))
          ..limit(1))
        .getSingleOrNull();

    final int entryId;
    if (existing != null) {
      entryId = existing.id;
      await (update(entries)..where((e) => e.id.equals(existing.id)))
          .write(EntriesCompanion(quantity: Value(existing.quantity + quantity)));
    } else {
      entryId = await into(entries).insert(EntriesCompanion.insert(
        listId: listId,
        cardId: cardId,
        finish: finish,
        language: language,
        condition: condition,
        quantity: quantity,
        addedAt: _now(),
        snapName: name,
        snapSetCode: setCode,
        snapSetName: Value(setName),
        snapCollector: collectorNumber,
      ));
    }
    await _touch(listId);
    return entryId;
  }

  Future<Entry?> entryById(int id) =>
      (select(entries)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<List<Entry>> entriesIn(int listId) => (select(entries)
        ..where((e) => e.listId.equals(listId))
        ..orderBy([(e) => OrderingTerm.desc(e.addedAt)]))
      .get();

  Stream<List<Entry>> watchEntries(int listId) => (select(entries)
        ..where((e) => e.listId.equals(listId))
        ..orderBy([(e) => OrderingTerm.desc(e.addedAt)]))
      .watch();

  /// Set an entry's quantity, deleting it at zero.
  ///
  /// Zero deletes rather than erroring, because the stepper's `−` is the natural
  /// way to undo a bad scan and stopping at 1 would leave a row the user has to
  /// remove by a second, different gesture.
  Future<void> setQuantity(int entryId, int quantity) async {
    final row = await entryById(entryId);
    if (row == null) return;
    if (quantity <= 0) {
      await (delete(entries)..where((e) => e.id.equals(entryId))).go();
    } else {
      await (update(entries)..where((e) => e.id.equals(entryId)))
          .write(EntriesCompanion(quantity: Value(quantity)));
    }
    await _touch(row.listId);
  }

  Future<void> removeEntry(int entryId) async {
    final row = await entryById(entryId);
    if (row == null) return;
    await (delete(entries)..where((e) => e.id.equals(entryId))).go();
    await _touch(row.listId);
  }

  /// Change an entry's printing or variant.
  ///
  /// Merges instead of failing when the target variant already exists in the
  /// list: editing a row into a shape another row already has is the user saying
  /// these are the same thing, and the `UNIQUE` constraint would otherwise throw
  /// where the intent was obvious.
  Future<int> updateEntry(
    int entryId, {
    String? cardId,
    String? name,
    String? setCode,
    String? setName,
    String? collectorNumber,
    int? finish,
    String? language,
    int? condition,
  }) async {
    final row = await entryById(entryId);
    if (row == null) return entryId;

    final target = (
      cardId: cardId ?? row.cardId,
      finish: finish ?? row.finish,
      language: language ?? row.language,
      condition: condition ?? row.condition,
    );

    final clash = await (select(entries)
          ..where((e) =>
              e.listId.equals(row.listId) &
              e.id.equals(entryId).not() &
              e.cardId.equals(target.cardId) &
              e.finish.equals(target.finish) &
              e.language.equals(target.language) &
              e.condition.equals(target.condition))
          ..limit(1))
        .getSingleOrNull();

    if (clash != null) {
      await (update(entries)..where((e) => e.id.equals(clash.id)))
          .write(EntriesCompanion(quantity: Value(clash.quantity + row.quantity)));
      await (delete(entries)..where((e) => e.id.equals(entryId))).go();
      await _touch(row.listId);
      return clash.id;
    }

    await (update(entries)..where((e) => e.id.equals(entryId))).write(
      EntriesCompanion(
        cardId: Value(target.cardId),
        finish: Value(target.finish),
        language: Value(target.language),
        condition: Value(target.condition),
        snapName: name == null ? const Value.absent() : Value(name),
        snapSetCode: setCode == null ? const Value.absent() : Value(setCode),
        snapSetName: setName == null ? const Value.absent() : Value(setName),
        snapCollector: collectorNumber == null
            ? const Value.absent()
            : Value(collectorNumber),
      ),
    );
    await _touch(row.listId);
    return entryId;
  }

  /// Copy entries into another list, merging with whatever is already there.
  Future<void> copyTo(Iterable<int> entryIds, int targetListId) =>
      _moveOrCopy(entryIds, targetListId, removeSource: false);

  /// Move entries into another list.
  Future<void> cutTo(Iterable<int> entryIds, int targetListId) =>
      _moveOrCopy(entryIds, targetListId, removeSource: true);

  Future<void> _moveOrCopy(
    Iterable<int> entryIds,
    int targetListId, {
    required bool removeSource,
  }) async {
    await transaction(() async {
      for (final id in entryIds) {
        final row = await entryById(id);
        if (row == null || row.listId == targetListId) continue;
        await addCard(
          listId: targetListId,
          cardId: row.cardId,
          name: row.snapName,
          setCode: row.snapSetCode,
          setName: row.snapSetName,
          collectorNumber: row.snapCollector,
          finish: row.finish,
          language: row.language,
          condition: row.condition,
          quantity: row.quantity,
        );
        if (removeSource) {
          await (delete(entries)..where((e) => e.id.equals(id))).go();
          await _touch(row.listId);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Counts
  // ---------------------------------------------------------------------------

  /// Total copies and distinct rows for a list — the "12 cards · 9 unique" line.
  Future<({int copies, int unique})> countsFor(int listId) async {
    final q = selectOnly(entries)
      ..addColumns([entries.quantity.sum(), entries.id.count()])
      ..where(entries.listId.equals(listId));
    final row = await q.getSingle();
    return (
      copies: row.read(entries.quantity.sum()) ?? 0,
      unique: row.read(entries.id.count()) ?? 0,
    );
  }

  /// Copies per list, for the lists folder. One query, not one per list.
  Future<Map<int, ({int copies, int unique})>> countsForAll() async {
    final q = selectOnly(entries)
      ..addColumns([entries.listId, entries.quantity.sum(), entries.id.count()])
      ..groupBy([entries.listId]);
    return {
      for (final row in await q.get())
        row.read(entries.listId)!: (
          copies: row.read(entries.quantity.sum()) ?? 0,
          unique: row.read(entries.id.count()) ?? 0,
        ),
    };
  }

  /// Which printings of [cardId] are already in [listId], for the picker's badge.
  Future<List<Entry>> entriesForCard(int listId, String cardId) =>
      (select(entries)
            ..where((e) => e.listId.equals(listId) & e.cardId.equals(cardId)))
          .get();

  /// Every copy of a card in a list, **across printings**.
  ///
  /// What the variant editor opens on. Keying it by printing was wrong: a copy
  /// that differs only by edition is exactly the kind of "these cannot be one
  /// row" the editor exists for, so changing a variant's edition and reopening
  /// must still show it.
  Future<List<Entry>> entriesForCardName(int listId, String name) =>
      (select(entries)
            ..where((e) => e.listId.equals(listId) & e.snapName.equals(name))
            ..orderBy([(e) => OrderingTerm.asc(e.addedAt)]))
          .get();

  /// Replace every copy of [name] in [listId] with exactly [wanted].
  ///
  /// The variant editor opens prepopulated with what the list already holds, so
  /// applying it is a **rewrite, not a diff the caller has to compute**: a
  /// variant the user cleared is gone, one they added is appended, and one they
  /// left alone keeps its `added_at` and therefore its place in scan order.
  ///
  /// **Keyed by card name, across printings.** Each wanted row names the
  /// printing it belongs to, so changing a row's edition moves it without
  /// leaving the set — which is the whole reason it is not keyed by printing.
  ///
  /// Quantities are only written where [VariantEdit.quantity] says so — an
  /// untouched variant keeps the count it had, which is what makes "open the
  /// editor, change nothing, apply" a genuine no-op rather than a silent reset
  /// to one.
  ///
  /// Runs in one transaction: a half-applied variant set is a state the user
  /// never asked for and cannot easily recognise.
  Future<void> setVariantsFor({
    required int listId,
    required String name,
    required List<VariantEdit> wanted,
    required VariantPrinting base,
  }) async {
    await transaction(() async {
      final existing = await entriesForCardName(listId, name);
      final byKey = {
        for (final e in existing)
          (e.cardId, e.finish, e.language, e.condition): e,
      };

      final keep = <int>{};
      for (final w in wanted) {
        final printing = w.printing ?? base;
        final key = (printing.cardId, w.finish, w.language, w.condition);
        final row = byKey[key];

        if (row == null) {
          await addCard(
            listId: listId,
            cardId: printing.cardId,
            name: printing.name,
            setCode: printing.setCode,
            setName: printing.setName,
            collectorNumber: printing.collectorNumber,
            finish: w.finish,
            language: w.language,
            condition: w.condition,
            quantity: w.quantity ?? 1,
          );
          continue;
        }

        keep.add(row.id);
        if (w.quantity != null && w.quantity != row.quantity) {
          await (update(entries)..where((e) => e.id.equals(row.id)))
              .write(EntriesCompanion(quantity: Value(w.quantity!)));
        }
      }

      for (final e in existing) {
        if (!keep.contains(e.id)) {
          await (delete(entries)..where((r) => r.id.equals(e.id))).go();
        }
      }
      await _touch(listId);
    });
  }

  // ---------------------------------------------------------------------------

  Future<void> _touch(int listId) =>
      (update(lists)..where((l) => l.id.equals(listId)))
          .write(ListsCompanion(updatedAt: Value(_now())));

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'collection.db')),
      );
    });
