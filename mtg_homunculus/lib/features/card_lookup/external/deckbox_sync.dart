import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/collection_database.dart';
import 'deckbox/deckbox_client.dart';
import 'deckbox/deckbox_csv.dart';
import 'deckbox/deckbox_mapping.dart';
import 'external_dao.dart';
import 'session_store.dart';

/// What a pull came to.
sealed class PullOutcome {
  const PullOutcome();
}

final class Pulled extends PullOutcome {
  const Pulled(this.rows);
  final int rows;
}

/// Skipped: pulled within the cooldown, and not stale.
final class PullNotDue extends PullOutcome {
  const PullNotDue();
}

/// No session, or Deckbox turned it away. The account shows *Signed out*.
final class PullSignedOut extends PullOutcome {
  const PullSignedOut();
}

final class PullFailed extends PullOutcome {
  const PullFailed(this.message);
  final String message;
}

/// Accounts and pulls — the read side of the Deckbox integration (M2).
///
/// **Reads only.** Nothing here changes anything on Deckbox: logging in, finding
/// lists and exporting them. Pushing arrives with M3.
///
/// **One request at a time, app-wide.** Every Deckbox call goes through
/// [_serial], so opening three lists in quick succession queues three exports
/// instead of firing them together (the plan's politeness rule).
class DeckboxSync {
  DeckboxSync._();
  static final instance = DeckboxSync._();

  static const provider = 'deckbox';

  /// How long a pull is good for before opening the list pulls again.
  static const cooldown = Duration(minutes: 5);

  ExternalDao get _dao => CollectionDatabase.instance.externalDao;

  /// Ids of the lists being pulled — queued or running — for progress bars.
  final pulling = ValueNotifier<Set<int>>(const {});

  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  /// Logs in and, on success, saves the session and records the account and
  /// its lists.
  ///
  /// The lists come from the page the login lands on — Deckbox's home page,
  /// whose menu holds them (D2) — so adding an account costs no extra request.
  /// Returns the login's own result, and the account if one was saved.
  Future<({DeckboxLoginResult result, ExternalAccount? account})> login(
    String email,
    String password,
  ) =>
      _serial(() async {
        final client = DeckboxClient(onLog: AppLogger.d);
        try {
          final result = await client.login(email, password);
          final username = result.username;
          if (result.state != DeckboxSessionState.signedIn || username == null) {
            return (result: result, account: null);
          }

          final account = await _dao.upsertAccount(provider: provider, username: username);
          await SessionStore.save(
            account.id,
            DeckboxSession(username: username, cookies: client.cookies, savedAt: DateTime.now()),
          );
          try {
            await _dao.syncLists(account.id, _known(DeckboxClient.readLists(result.page.body)));
          } on DeckboxException catch (e) {
            // Signed in, but the menu did not read: the account still stands,
            // and its lists are found again on the next refresh.
            AppLogger.w('Deckbox lists not read at login: $e');
          }
          AppLogger.i('Deckbox account ${account.id} signed in as $username');
          return (result: result, account: account);
        } finally {
          client.close();
        }
      });

  /// Finds the account's lists again — the menu on Deckbox's home page.
  Future<void> refreshLists(ExternalAccount account) => _serial(() async {
        final session = await SessionStore.load(account.id);
        if (session == null) {
          await _dao.setSessionValid(account.id, false);
          return;
        }
        final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
        try {
          final (lists, _) = await client.findLists();
          await _dao.syncLists(account.id, _known(lists));
          await SessionStore.save(account.id, session.withCookies(client.cookies));
        } finally {
          client.close();
        }
      });

  /// *Log out* — forgets the session on this phone. The account, its lists and
  /// its mirror stay; it shows as *Signed out* until logged in again.
  Future<void> logOut(ExternalAccount account) async {
    await SessionStore.clear(account.id);
    await _dao.setSessionValid(account.id, false);
  }

  /// *Remove from this phone* — the account, its lists and mirror, and its
  /// session. Nothing on Deckbox changes.
  Future<void> removeAccount(ExternalAccount account) async {
    await SessionStore.clear(account.id);
    await _dao.removeAccount(account.id);
  }

  /// Only the three lists the app manages; decks and anything else are skipped
  /// for now (D2).
  static List<({int remoteId, String kind, String name})> _known(List<DeckboxListRef> found) => [
        for (final l in found)
          if (l.kind != DeckboxListKind.other)
            (remoteId: l.setId, kind: l.kind.name, name: l.name),
      ];

  // ---------------------------------------------------------------------------
  // Pulls
  // ---------------------------------------------------------------------------

  /// Pulls on opening a list — unless it was pulled within [cooldown] and is
  /// not stale.
  Future<PullOutcome> pullIfDue(ExternalList list) {
    final last = list.lastPulledAt;
    final fresh = last != null &&
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - last < cooldown.inSeconds;
    if (fresh && !list.stale) return Future.value(const PullNotDue());
    return pull(list);
  }

  /// Pulls one list: one export, mapped into the mirror in one transaction.
  ///
  /// Never throws. A failure is recorded on the list — and the previous mirror
  /// kept exactly as it was — so the list can say what went wrong. A list
  /// already queued is not queued twice.
  Future<PullOutcome> pull(ExternalList list) {
    final queued = _queued[list.id];
    if (queued != null) return queued;
    pulling.value = {...pulling.value, list.id};
    final run = _pull(list).whenComplete(() {
      _queued.remove(list.id);
      pulling.value = {...pulling.value}..remove(list.id);
    });
    return _queued[list.id] = run;
  }

  final _queued = <int, Future<PullOutcome>>{};

  Future<PullOutcome> _pull(ExternalList list) => _serial(() async {
        final watch = Stopwatch()..start();
        final account = await _dao.accountById(list.accountId);
        final session = account == null ? null : await SessionStore.load(account.id);
        if (account == null || session == null) {
          if (account != null) await _dao.setSessionValid(account.id, false);
          return const PullSignedOut();
        }

        final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
        try {
          final page = await client.exportCsv(list.remoteId, columns: 'Scryfall ID,Last Updated');
          if (!(page.contentType ?? '').contains('csv')) {
            // A signed-out export bounces to the login page, as HTML.
            final (state, _) = DeckboxClient.readSessionState(page.body);
            if (page.url.path.startsWith('/accounts/') || state == DeckboxSessionState.signedOut) {
              await _dao.setSessionValid(account.id, false);
              await _dao.recordPullError(list.id, 'Signed out');
              return const PullSignedOut();
            }
            throw DeckboxException('pull', 'the export came back as ${page.contentType}, not CSV');
          }

          final raw = DeckboxCsv.rows(page.body);
          final header = DeckboxCsv.parse(page.body).firstOrNull ?? const [];
          for (final column in const ['Count', 'Name', 'Printing Id', 'Scryfall ID']) {
            if (!header.contains(column)) {
              throw DeckboxException('pull', 'the export has no "$column" column');
            }
          }

          final rows = <DeckboxRow>[];
          for (var i = 0; i < raw.length; i++) {
            rows.add(await _resolve(DeckboxMapping.read(raw[i], i)));
          }

          await _dao.replaceMirror(
            list.id,
            [for (final r in rows) _companion(list.id, r)],
            pulledAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          await SessionStore.save(account.id, session.withCookies(client.cookies));
          await _dao.setSessionValid(account.id, true);
          watch.stop();
          AppLogger.i('Deckbox pull ${list.name}: ${rows.length} rows in ${watch.elapsedMilliseconds} ms');
          return Pulled(rows.length);
        } catch (e) {
          // Type and message only for a known failure; a raw exception's text
          // could quote a request, so it is reduced to its type.
          final message = e is DeckboxException || e is FormatException ? '$e' : '${e.runtimeType}';
          AppLogger.w('Deckbox pull ${list.name} failed: $message');
          await _dao.recordPullError(list.id, message);
          return PullFailed(message);
        } finally {
          client.close();
        }
      });

  /// An etched row exports no Scryfall id; its printing is found in the card
  /// cache by the base set and number (`mh2_e` #389 → `mh2` 389). Not found —
  /// or no card cache yet — leaves it unmapped, which the mirror shows.
  Future<DeckboxRow> _resolve(DeckboxRow row) async {
    final lookup = row.etchedLookup;
    if (lookup == null || row.cardId != null) return row;
    final card = await CardsDatabase.instance.cardBySetNumber(lookup.set, lookup.number);
    return card == null ? row : row.withCard(card.id);
  }

  static ExternalEntriesCompanion _companion(int listId, DeckboxRow r) =>
      ExternalEntriesCompanion.insert(
        listId: listId,
        position: r.position,
        count: r.count,
        tradeCount: Value(r.tradeCount),
        printingId: r.printingId,
        condition: r.condition,
        language: r.language,
        foil: r.foil,
        rowFlags: r.rowFlags,
        identityKey: r.identityKey,
        name: r.name,
        edition: r.edition,
        editionCode: r.editionCode,
        cardNumber: r.cardNumber,
        printingNote: r.printingNote,
        lastUpdated: Value(r.lastUpdated),
        anyPrinting: r.anyPrinting,
        cardId: Value(r.cardId),
        cardRef: Value(r.cardRef),
        finish: Value(r.finish),
        languageCode: Value(r.languageCode),
        conditionCode: Value(r.conditionCode),
      );
}
