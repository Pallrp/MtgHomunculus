import 'package:drift/drift.dart';

import '../data/collection_database.dart';
import '../models/deckbox_prefs.dart';
import 'external_tables.dart';

part 'external_dao.g.dart';

/// A mirrored list's counts: copies, copies for trade, rows, and rows with
/// any copy for trade — what a Tradelist counts as unique.
typedef ExternalCounts = ({int copies, int forTrade, int unique, int tradeUnique});

/// Queries for the mirror of another service's lists.
///
/// An accessor rather than more methods on [CollectionDatabase]: the app's own
/// lists and these mirrors share a file — one precious database, one place it
/// is backed up — but not a vocabulary.
/// A staged addition's version: a printing, or the card in any printing.
typedef StagedVersion = ({
  String name,
  String? cardId,
  String? cardRef,
  bool anyPrinting,
  String setCode,
  String setName,
  String collectorNumber,
});

@DriftAccessor(
  tables: [ExternalAccounts, ExternalLists, ExternalEntries, StagedChanges],
)
class ExternalDao extends DatabaseAccessor<CollectionDatabase>
    with _$ExternalDaoMixin {
  ExternalDao(super.db);

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  Stream<List<ExternalAccount>> watchAccounts() => (select(externalAccounts)
        ..orderBy([(a) => OrderingTerm.asc(a.createdAt)]))
      .watch();

  Future<ExternalAccount?> accountById(int id) =>
      (select(externalAccounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// The account for this username, created on first login.
  ///
  /// Logging in again as an account that is already here — after a log out or
  /// an expired session — finds that row and marks it signed in, so its lists,
  /// mirror and (from M3) staged changes are picked up where they were left.
  Future<ExternalAccount> upsertAccount({
    required String provider,
    required String username,
  }) async {
    final existing = await (select(externalAccounts)
          ..where((a) => a.provider.equals(provider) & a.username.equals(username)))
        .getSingleOrNull();
    if (existing != null) {
      await setSessionValid(existing.id, true);
      return (await accountById(existing.id))!;
    }
    final id = await into(externalAccounts).insert(ExternalAccountsCompanion.insert(
      provider: provider,
      username: username,
      createdAt: _now(),
    ));
    return (await accountById(id))!;
  }

  Future<void> setSessionValid(int accountId, bool valid) =>
      (update(externalAccounts)..where((a) => a.id.equals(accountId)))
          .write(ExternalAccountsCompanion(sessionValid: Value(valid)));

  /// *Remove from this phone* — the account, and by cascade its lists and
  /// mirror. Nothing on the service changes. The caller clears the session.
  Future<void> removeAccount(int accountId) =>
      (delete(externalAccounts)..where((a) => a.id.equals(accountId))).go();

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  /// Every mirrored list, grouped by account, Inventory → Tradelist → Wishlist.
  Stream<List<ExternalList>> watchLists() =>
      select(externalLists).watch().map(_ordered);

  Future<List<ExternalList>> listsFor(int accountId) async => _ordered(
        await (select(externalLists)..where((l) => l.accountId.equals(accountId))).get(),
      );

  Future<ExternalList?> listById(int id) =>
      (select(externalLists)..where((l) => l.id.equals(id))).getSingleOrNull();

  Stream<ExternalList?> watchList(int id) =>
      (select(externalLists)..where((l) => l.id.equals(id))).watchSingleOrNull();

  /// Records the lists found on the service, keeping the ids of ones already
  /// here. A list that has disappeared from the service is **left**, not
  /// deleted: its mirror is the user's last view of it, and losing it silently
  /// is worse than showing one stale list.
  Future<void> syncLists(
    int accountId,
    List<({int remoteId, String kind, String name})> found,
  ) =>
      transaction(() async {
        for (final f in found) {
          final existing = await (select(externalLists)
                ..where((l) => l.accountId.equals(accountId) & l.remoteId.equals(f.remoteId)))
              .getSingleOrNull();
          if (existing == null) {
            await into(externalLists).insert(ExternalListsCompanion.insert(
              accountId: accountId,
              remoteId: f.remoteId,
              kind: f.kind,
              name: f.name,
            ));
          } else if (existing.name != f.name || existing.kind != f.kind) {
            await (update(externalLists)..where((l) => l.id.equals(existing.id)))
                .write(ExternalListsCompanion(name: Value(f.name), kind: Value(f.kind)));
          }
        }
      });

  Future<void> markStale(int listId) =>
      (update(externalLists)..where((l) => l.id.equals(listId)))
          .write(const ExternalListsCompanion(stale: Value(true)));

  Future<void> setAnyPrinting(int listId, bool on) =>
      (update(externalLists)..where((l) => l.id.equals(listId)))
          .write(ExternalListsCompanion(anyPrinting: Value(on)));

  /// A failed pull: the reason is kept for the list to show, and the previous
  /// mirror is left exactly as it was.
  Future<void> recordPullError(int listId, String message) =>
      (update(externalLists)..where((l) => l.id.equals(listId)))
          .write(ExternalListsCompanion(lastPullError: Value(message)));

  // ---------------------------------------------------------------------------
  // The mirror
  // ---------------------------------------------------------------------------

  /// Replaces a list's mirror with a fresh pull — **all or nothing**.
  ///
  /// In one transaction: the old rows go, the new ones arrive, and the list is
  /// marked pulled, no longer stale, with no error. If anything throws, the
  /// previous mirror is untouched.
  Future<void> replaceMirror(
    int listId,
    List<ExternalEntriesCompanion> rows, {
    required int pulledAt,
  }) =>
      transaction(() async {
        await (delete(externalEntries)..where((e) => e.listId.equals(listId))).go();
        await batch((b) => b.insertAll(externalEntries, rows));
        await (update(externalLists)..where((l) => l.id.equals(listId))).write(
          ExternalListsCompanion(
            lastPulledAt: Value(pulledAt),
            stale: const Value(false),
            lastPullError: const Value(null),
          ),
        );
      });

  // ---------------------------------------------------------------------------
  // One mirror for an Inventory and its Tradelist (tradelist.md, schema 4)
  // ---------------------------------------------------------------------------

  /// The Inventory a Tradelist is a view of — the same account's. Null for any
  /// other list, or when the account has no Inventory.
  Future<ExternalList?> inventoryFor(ExternalList list) async {
    if (list.kind != 'tradelist') return null;
    return (await listsFor(list.accountId)).where((l) => l.kind == 'inventory').firstOrNull;
  }

  /// The list whose rows [list] shows. On Deckbox a Tradelist **is** its
  /// Inventory's rows, with a count for trade on each — so it stores none of
  /// its own and reads the Inventory's.
  Future<int> mirrorIdOf(ExternalList list) async => (await inventoryFor(list))?.id ?? list.id;

  /// Every list showing the mirror stored under [mirrorId]: the list itself
  /// and, for an Inventory, its account's Tradelist.
  Future<List<ExternalList>> listsSharing(int mirrorId) async {
    final owner = await listById(mirrorId);
    if (owner == null) return const [];
    return [
      owner,
      if (owner.kind == 'inventory')
        for (final l in await listsFor(owner.accountId)) if (l.kind == 'tradelist') l,
    ];
  }

  /// A list marked pulled without rows of its own — a Tradelist, when its
  /// Inventory was.
  Future<void> markPulled(int listId, int pulledAt) =>
      (update(externalLists)..where((l) => l.id.equals(listId))).write(
        ExternalListsCompanion(
          lastPulledAt: Value(pulledAt),
          stale: const Value(false),
          lastPullError: const Value(null),
        ),
      );

  /// A row edit, confirmed on Deckbox, applied to the mirror without a pull
  /// (mirror_editing.md). [changes] carries the row's new fields and identity.
  ///
  /// In one transaction:
  ///
  /// - **A row already of the new variant is folded in**, as Deckbox does: one
  ///   row with both counts, the rows after the other moving up a place so
  ///   positions stay the export's. (Which row id Deckbox keeps varies — E4
  ///   kept the edited one, a device test the other — but the mirror's ids
  ///   are its own; the edited row's is kept, so a screen on it stays.)
  /// - **Staged removals and Tradelist marks follow the row** — re-keyed, with
  ///   the new variant shown. One meeting its twin's on a folded row adds up,
  ///   capped at what the row holds. Additions are left alone: they are cards
  ///   in hand, and find their row by variant.
  /// - Every list showing the mirror is revalidated.
  /// Another mirror row already of the variant [identityKey] — what an edit of
  /// [row] into it folds into.
  Future<ExternalEntry?> twinOf(ExternalEntry row, String identityKey) => (select(externalEntries)
        ..where((e) => e.listId.equals(row.listId) & e.identityKey.equals(identityKey) & e.id.equals(row.id).not())
        ..limit(1))
      .getSingleOrNull();

  Future<void> applyRowEdit(ExternalEntry row, ExternalEntriesCompanion changes) => transaction(() async {
        var c = changes;
        final twin = await twinOf(row, changes.identityKey.value);
        if (twin != null) {
          c = c.copyWith(count: Value(row.count + twin.count), tradeCount: Value(row.tradeCount + twin.tradeCount));
          await (delete(externalEntries)..where((e) => e.id.equals(twin.id))).go();
          await customUpdate(
            'UPDATE external_entries SET position = position - 1 WHERE list_id = ? AND position > ?',
            variables: [Variable.withInt(row.listId), Variable.withInt(twin.position)],
            updates: {externalEntries},
          );
        }
        await (update(externalEntries)..where((e) => e.id.equals(row.id))).write(c);
        final edited = await (select(externalEntries)..where((e) => e.id.equals(row.id))).getSingle();

        for (final list in await listsSharing(row.listId)) {
          final following = await (select(stagedChanges)
                ..where((s) => s.listId.equals(list.id) & s.identityKey.equals(row.identityKey)))
              .get();
          for (final s in following) {
            final mark = s.direction == 'add';
            final key = mark ? markKey(edited) : edited.identityKey;
            final cap = mark ? freeOf(edited) : countOn(list, edited);
            final met = await _staged(list.id, s.direction, key);
            final quantity = ((met?.quantity ?? 0) + s.quantity).clamp(0, cap);
            if (met != null) {
              await (delete(stagedChanges)..where((x) => x.id.equals(s.id))).go();
              await setStagedQuantity(met.id, quantity);
              continue;
            }
            if (quantity == 0) {
              await (delete(stagedChanges)..where((x) => x.id.equals(s.id))).go();
              continue;
            }
            await (update(stagedChanges)..where((x) => x.id.equals(s.id))).write(StagedChangesCompanion(
              stageKey: Value(key),
              identityKey: Value(edited.identityKey),
              quantity: Value(quantity),
              cardId: Value(edited.cardId),
              cardRef: Value(edited.cardRef),
              anyPrinting: Value(edited.anyPrinting),
              finish: Value(edited.finish),
              languageCode: Value(edited.languageCode),
              conditionCode: Value(edited.conditionCode),
              setCode: Value(edited.editionCode),
              setName: Value(edited.edition),
              collectorNumber: Value(edited.cardNumber),
              flag: const Value(null),
            ));
          }
          await revalidate(list);
        }
      });

  Stream<List<ExternalEntry>> watchEntries(int listId) => (select(externalEntries)
        ..where((e) => e.listId.equals(listId))
        ..orderBy([(e) => OrderingTerm.asc(e.position)]))
      .watch();

  /// Copies, copies for trade, and rows per mirrored list, for the lists
  /// folder. One query. A Tradelist stores no rows: the folder shows it its
  /// Inventory's [ExternalCounts.forTrade] and [ExternalCounts.tradeUnique].
  Stream<Map<int, ExternalCounts>> watchCounts() {
    const tradeRows = CustomExpression<int>('SUM(CASE WHEN trade_count > 0 THEN 1 ELSE 0 END)');
    final q = selectOnly(externalEntries)
      ..addColumns([
        externalEntries.listId,
        externalEntries.count.sum(),
        externalEntries.tradeCount.sum(),
        externalEntries.id.count(),
        tradeRows,
      ])
      ..groupBy([externalEntries.listId]);
    return q.watch().map((rows) => {
          for (final r in rows)
            r.read(externalEntries.listId)!: (
              copies: r.read(externalEntries.count.sum()) ?? 0,
              forTrade: r.read(externalEntries.tradeCount.sum()) ?? 0,
              unique: r.read(externalEntries.id.count()) ?? 0,
              tradeUnique: r.read(tradeRows) ?? 0,
            ),
        });
  }

  // ---------------------------------------------------------------------------
  // Staged changes (M3)
  // ---------------------------------------------------------------------------

  /// The count a staged change on [list] works against: copies owned, except
  /// on a Tradelist, whose rows are Inventory rows and whose count is the one
  /// **for trade** (D8).
  static int countOn(ExternalList list, ExternalEntry row) =>
      list.kind == 'tradelist' ? row.tradeCount : row.count;

  Stream<List<StagedChange>> watchStaged(int listId) => (select(stagedChanges)
        ..where((s) => s.listId.equals(listId))
        ..orderBy([(s) => OrderingTerm.asc(s.stagedAt)]))
      .watch();

  Future<List<StagedChange>> stagedFor(int listId) => (select(stagedChanges)
        ..where((s) => s.listId.equals(listId))
        ..orderBy([(s) => OrderingTerm.asc(s.stagedAt)]))
      .get();

  Future<StagedChange?> stagedById(int id) =>
      (select(stagedChanges)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// The key an addition is staged under: its printing — or, for a generic
  /// one, its card name — and its variant. Staging the same again adds up.
  static String additionKey({
    required String name,
    required String? cardId,
    required bool anyPrinting,
    required int? finish,
    required String? languageCode,
    required int? conditionCode,
  }) =>
      [
        anyPrinting ? 'any:$name' : cardId ?? 'name:$name',
        finish ?? '',
        languageCode ?? '',
        conditionCode ?? '',
      ].join('|');

  /// Stages copies to add. Staging the same thing again raises the quantity
  /// — and keeps the staged row's own *for trade* flag.
  ///
  /// [forTrade] left null takes **Also put additions up for trade** on an
  /// Inventory ([DeckboxPrefs.alsoForTrade]) and false anywhere else.
  /// Returns the staged row's id.
  Future<int> stageAddition({
    required int listId,
    required String name,
    required String? cardId,
    required String? cardRef,
    required bool anyPrinting,
    required int? finish,
    required String? languageCode,
    required int? conditionCode,
    String setCode = '',
    String setName = '',
    String collectorNumber = '',
    int quantity = 1,
    bool? forTrade,
  }) async {
    final trade = forTrade ?? ((await listById(listId))?.kind == 'inventory' && DeckboxPrefs.alsoForTrade.value);
    final key = additionKey(
      name: name,
      cardId: cardId,
      anyPrinting: anyPrinting,
      finish: finish,
      languageCode: languageCode,
      conditionCode: conditionCode,
    );
    return transaction(() async {
      final existing = await _staged(listId, 'add', key);
      if (existing != null) {
        await (update(stagedChanges)..where((s) => s.id.equals(existing.id))).write(
            StagedChangesCompanion(quantity: Value(existing.quantity + quantity)));
        return existing.id;
      }
      return into(stagedChanges).insert(StagedChangesCompanion.insert(
        listId: listId,
        direction: 'add',
        quantity: quantity,
        stageKey: key,
        name: name,
        cardId: Value(cardId),
        cardRef: Value(cardRef),
        anyPrinting: Value(anyPrinting),
        finish: Value(finish),
        languageCode: Value(languageCode),
        conditionCode: Value(conditionCode),
        setCode: Value(setCode),
        setName: Value(setName),
        collectorNumber: Value(collectorNumber),
        forTrade: Value(trade),
        stagedAt: _now(),
      ));
    });
  }

  /// A staged Inventory addition's *also up for trade*, from its detail.
  Future<void> setForTrade(int id, bool value) =>
      (update(stagedChanges)..where((s) => s.id.equals(id))).write(StagedChangesCompanion(forTrade: Value(value)));

  /// Edits a staged addition — its chips, or its version — in place. An edit
  /// that makes it the same as another staged addition **merges** the two, as
  /// an app list's entries do. Returns the id the addition now lives under.
  ///
  /// An absent [Value] leaves that attribute; `Value(null)` unsets it, which
  /// only a generic row means (*any condition*). An edit clears the row's last
  /// error: what was refused is not what will be sent.
  Future<int> updateStagedAddition(
    int id, {
    Value<int?> finish = const Value.absent(),
    Value<String?> languageCode = const Value.absent(),
    Value<int?> conditionCode = const Value.absent(),
    StagedVersion? version,
  }) =>
      transaction(() async {
        final s = await (select(stagedChanges)..where((x) => x.id.equals(id))).getSingle();
        final next = s.copyWith(
          finish: finish,
          languageCode: languageCode,
          conditionCode: conditionCode,
          name: version?.name,
          cardId: version == null ? const Value.absent() : Value(version.cardId),
          cardRef: version == null ? const Value.absent() : Value(version.cardRef),
          anyPrinting: version?.anyPrinting,
          setCode: version?.setCode,
          setName: version?.setName,
          collectorNumber: version?.collectorNumber,
          lastError: const Value(null),
        );
        final key = additionKey(
          name: next.name,
          cardId: next.cardId,
          anyPrinting: next.anyPrinting,
          finish: next.finish,
          languageCode: next.languageCode,
          conditionCode: next.conditionCode,
        );
        final twin = await _staged(s.listId, 'add', key);
        if (twin != null && twin.id != id) {
          await (update(stagedChanges)..where((x) => x.id.equals(twin.id)))
              .write(StagedChangesCompanion(quantity: Value(twin.quantity + s.quantity)));
          await (delete(stagedChanges)..where((x) => x.id.equals(id))).go();
          return twin.id;
        }
        await update(stagedChanges).replace(next.copyWith(stageKey: key));
        return id;
      });

  /// Stages one more copy of a mirrored row, in its exact variant — the
  /// row's **+**. An etched row's Deckbox edition (`mh2_e`) is staged under
  /// its base set, which is how an etched addition is written (D4 p7).
  Future<int> stageAdditionLike(ExternalEntry row) => stageAddition(
        listId: row.listId,
        name: row.name,
        cardId: row.cardId,
        cardRef: row.cardRef,
        anyPrinting: row.anyPrinting,
        finish: row.finish,
        languageCode: row.languageCode,
        conditionCode: row.conditionCode,
        setCode: row.editionCode.toLowerCase().replaceFirst(RegExp(r'_e$'), ''),
        setName: row.edition,
        collectorNumber: row.cardNumber,
      );

  /// Copies of an Inventory row owned and **not yet for trade** — what a
  /// Tradelist addition can mark.
  static int freeOf(ExternalEntry row) => row.count - row.tradeCount;

  /// The stage key of a Tradelist addition marking [row].
  static String markKey(ExternalEntry row) => 'mark:${row.identityKey}';

  /// Stages copies of an Inventory row to **mark for trade** — a Tradelist
  /// addition (tradelist.md, decision 2: the Tradelist only marks owned
  /// copies; it never adds to the Inventory). **Capped** at the row's free
  /// copies less what is already staged to mark. Returns how many were
  /// staged; 0 when nothing is free.
  Future<int> stageMark({
    required ExternalList list,
    required ExternalEntry row,
    int quantity = 1,
  }) =>
      transaction(() async {
        final key = markKey(row);
        final existing = await _staged(list.id, 'add', key);
        final already = existing?.quantity ?? 0;
        final take = (freeOf(row) - already).clamp(0, quantity);
        if (take == 0) return 0;
        if (existing != null) {
          await (update(stagedChanges)..where((s) => s.id.equals(existing.id)))
              .write(StagedChangesCompanion(quantity: Value(already + take)));
        } else {
          await into(stagedChanges).insert(StagedChangesCompanion.insert(
            listId: list.id,
            direction: 'add',
            quantity: take,
            stageKey: key,
            name: row.name,
            cardId: Value(row.cardId),
            cardRef: Value(row.cardRef),
            anyPrinting: Value(row.anyPrinting),
            finish: Value(row.finish),
            languageCode: Value(row.languageCode),
            conditionCode: Value(row.conditionCode),
            setCode: Value(row.editionCode),
            setName: Value(row.edition),
            collectorNumber: Value(row.cardNumber),
            identityKey: Value(row.identityKey),
            stagedAt: _now(),
          ));
        }
        return take;
      });

  /// Stages copies of a mirrored row to remove — **capped** at what the row
  /// holds less what is already staged against it. Returns how many were
  /// actually staged; 0 when the row has nothing left to give.
  Future<int> stageRemoval({
    required ExternalList list,
    required ExternalEntry row,
    int quantity = 1,
  }) =>
      transaction(() async {
        final existing = await _staged(list.id, 'remove', row.identityKey);
        final already = existing?.quantity ?? 0;
        final take = (countOn(list, row) - already).clamp(0, quantity);
        if (take == 0) return 0;
        if (existing != null) {
          await (update(stagedChanges)..where((s) => s.id.equals(existing.id)))
              .write(StagedChangesCompanion(quantity: Value(already + take)));
        } else {
          await into(stagedChanges).insert(StagedChangesCompanion.insert(
            listId: list.id,
            direction: 'remove',
            quantity: take,
            stageKey: row.identityKey,
            name: row.name,
            cardId: Value(row.cardId),
            cardRef: Value(row.cardRef),
            anyPrinting: Value(row.anyPrinting),
            finish: Value(row.finish),
            languageCode: Value(row.languageCode),
            conditionCode: Value(row.conditionCode),
            setCode: Value(row.editionCode),
            setName: Value(row.edition),
            collectorNumber: Value(row.cardNumber),
            identityKey: Value(row.identityKey),
            stagedAt: _now(),
          ));
        }
        return take;
      });

  /// Sets a staged change's quantity; 0 unstages it.
  Future<void> setStagedQuantity(int id, int quantity) => quantity <= 0
      ? (delete(stagedChanges)..where((s) => s.id.equals(id))).go()
      : (update(stagedChanges)..where((s) => s.id.equals(id)))
          .write(StagedChangesCompanion(quantity: Value(quantity)));

  Future<void> unstage(Iterable<int> ids) =>
      (delete(stagedChanges)..where((s) => s.id.isIn(ids))).go();

  /// After a pull: flag every staged removal the fresh mirror can no longer
  /// satisfy, and clear the flag on one it can again. Additions are never
  /// flagged — adding is always possible. **Nothing is clamped**; the user
  /// decides.
  Future<void> revalidate(ExternalList list) => transaction(() async {
        final mirrorId = await mirrorIdOf(list);
        final rows = await (select(externalEntries)..where((e) => e.listId.equals(mirrorId))).get();
        final byIdentity = <String, List<ExternalEntry>>{};
        for (final r in rows) {
          (byIdentity[r.identityKey] ??= []).add(r);
        }
        // A Tradelist's additions are marks on Inventory rows (tradelist.md,
        // step 4) — checked as removals are, against the row's free copies.
        final marks = list.kind == 'tradelist';
        final checked = await (select(stagedChanges)
              ..where((s) =>
                  s.listId.equals(list.id) &
                  (marks ? s.direction.isIn(const ['remove', 'add']) : s.direction.equals('remove'))))
            .get();
        for (final s in checked) {
          final mark = s.direction == 'add';
          final matches = byIdentity[s.identityKey] ?? const <ExternalEntry>[];
          final String? flag;
          if (mark && s.identityKey == null) {
            // Staged before additions to a Tradelist meant marking a row.
            flag = 'unmatched';
          } else if (matches.isEmpty) {
            flag = 'gone';
          } else if (matches.length > 1) {
            flag = 'ambiguous';
          } else {
            final have = mark ? freeOf(matches.single) : countOn(list, matches.single);
            flag = have < s.quantity ? 'short:$have' : null;
          }
          if (flag != s.flag) {
            await (update(stagedChanges)..where((x) => x.id.equals(s.id)))
                .write(StagedChangesCompanion(flag: Value(flag)));
          }
        }
      });

  /// Just before a request goes out: when, and what the row's count should be
  /// once it lands.
  Future<void> markSent(int id, int expectedCount) =>
      (update(stagedChanges)..where((s) => s.id.equals(id))).write(StagedChangesCompanion(
        sentAt: Value(_now()),
        expectedCount: Value(expectedCount),
        lastError: const Value(null),
      ));

  /// The request did not land (or was never sent): ready to go again.
  Future<void> clearSent(int id, {String? error}) =>
      (update(stagedChanges)..where((s) => s.id.equals(id))).write(StagedChangesCompanion(
        sentAt: const Value(null),
        expectedCount: const Value(null),
        lastError: Value(error),
      ));

  Future<void> recordStagedError(int id, String error) =>
      (update(stagedChanges)..where((s) => s.id.equals(id)))
          .write(StagedChangesCompanion(lastError: Value(error)));

  /// Staged changes per list, for the lists folder's *N staged* tag.
  Stream<Map<int, int>> watchStagedCounts() {
    final q = selectOnly(stagedChanges)
      ..addColumns([stagedChanges.listId, stagedChanges.id.count()])
      ..groupBy([stagedChanges.listId]);
    return q.watch().map((rows) => {
          for (final r in rows) r.read(stagedChanges.listId)!: r.read(stagedChanges.id.count()) ?? 0,
        });
  }

  Future<StagedChange?> _staged(int listId, String direction, String key) => (select(stagedChanges)
        ..where((s) =>
            s.listId.equals(listId) & s.direction.equals(direction) & s.stageKey.equals(key)))
      .getSingleOrNull();

  // ---------------------------------------------------------------------------

  static const _kindOrder = ['inventory', 'tradelist', 'wishlist'];

  static List<ExternalList> _ordered(List<ExternalList> lists) => lists
    ..sort((a, b) {
      final byAccount = a.accountId.compareTo(b.accountId);
      if (byAccount != 0) return byAccount;
      final ka = _kindOrder.indexOf(a.kind), kb = _kindOrder.indexOf(b.kind);
      return (ka < 0 ? 99 : ka).compareTo(kb < 0 ? 99 : kb);
    });

  static int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
