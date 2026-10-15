import 'package:drift/drift.dart';

import '../data/collection_database.dart';
import 'external_tables.dart';

part 'external_dao.g.dart';

typedef ExternalCounts = ({int copies, int forTrade, int unique});

/// Queries for the mirror of another service's lists.
///
/// An accessor rather than more methods on [CollectionDatabase]: the app's own
/// lists and these mirrors share a file — one precious database, one place it
/// is backed up — but not a vocabulary.
@DriftAccessor(tables: [ExternalAccounts, ExternalLists, ExternalEntries])
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

  Stream<List<ExternalEntry>> watchEntries(int listId) => (select(externalEntries)
        ..where((e) => e.listId.equals(listId))
        ..orderBy([(e) => OrderingTerm.asc(e.position)]))
      .watch();

  /// Copies, copies for trade, and rows per mirrored list, for the lists
  /// folder. One query. A Tradelist shows [ExternalCounts.forTrade] — its rows
  /// are Inventory rows, and what it lists is the count for trade.
  Stream<Map<int, ExternalCounts>> watchCounts() {
    final q = selectOnly(externalEntries)
      ..addColumns([
        externalEntries.listId,
        externalEntries.count.sum(),
        externalEntries.tradeCount.sum(),
        externalEntries.id.count(),
      ])
      ..groupBy([externalEntries.listId]);
    return q.watch().map((rows) => {
          for (final r in rows)
            r.read(externalEntries.listId)!: (
              copies: r.read(externalEntries.count.sum()) ?? 0,
              forTrade: r.read(externalEntries.tradeCount.sum()) ?? 0,
              unique: r.read(externalEntries.id.count()) ?? 0,
            ),
        });
  }

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
