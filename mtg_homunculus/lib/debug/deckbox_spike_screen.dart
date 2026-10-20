import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../features/card_lookup/data/cards_database.dart' show CardsDatabase;
import '../features/card_lookup/data/collection_database.dart';
import '../features/card_lookup/external/deckbox/deckbox_client.dart';
import '../features/card_lookup/external/deckbox/deckbox_csv.dart';
import '../features/card_lookup/external/deckbox/deckbox_mapping.dart';
import '../features/card_lookup/external/deckbox/deckbox_row_panel.dart';
import '../features/card_lookup/external/deckbox_sync.dart';
import '../features/card_lookup/external/session_store.dart';
import '../features/card_lookup/models/dev_flags.dart';
import '../features/card_lookup/widgets/deckbox_login_dialog.dart';

/// The Deckbox spikes (M1), one button per step, run on the real device.
///
/// **Every step but logging in is guarded.** It acts only on the stored
/// account whose username — as Deckbox's own page reported it — equals
/// [DevFlags.deckboxTestUser], with that account's session. Logging in is
/// always allowed, because it is the user's own action; acting on whatever
/// account they logged into is not. Since M2 the spike signs in through the
/// app's own account flow, so the test account also appears in the lists
/// folder.
///
/// Each step writes a record to `<app documents>/deckbox_spike/`, pulled over
/// ADB like `app_log.txt`. Records are redacted: no cookie values, no
/// anti-forgery token, never the password.
class DeckboxSpikeScreen extends StatefulWidget {
  const DeckboxSpikeScreen({super.key});

  @override
  State<DeckboxSpikeScreen> createState() => _DeckboxSpikeScreenState();
}

class _DeckboxSpikeScreenState extends State<DeckboxSpikeScreen> {
  late final _testUser =
      TextEditingController(text: DevFlags.deckboxTestUser.value);
  ExternalAccount? _account;
  DeckboxSession? _session;
  bool _busy = false;
  String _output = '';
  String _outDir = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _testUser.dispose();
    super.dispose();
  }

  /// The test account, if it is stored, and its session.
  Future<void> _reload() async {
    final dir = await getApplicationDocumentsDirectory();
    final expected = DevFlags.deckboxTestUser.value;
    final accounts = await CollectionDatabase.instance.externalDao.watchAccounts().first;
    final account = accounts.where((a) => a.username == expected).firstOrNull;
    final session = account == null ? null : await SessionStore.load(account.id);
    if (!mounted) return;
    setState(() {
      _account = account;
      _session = session;
      _outDir = '${dir.path}/deckbox_spike';
    });
  }

  bool get _guardOk {
    final s = _session;
    final expected = DevFlags.deckboxTestUser.value;
    return s != null && expected.isNotEmpty && s.username == expected;
  }

  String get _guardText {
    final s = _session;
    if (DevFlags.deckboxTestUser.value.isEmpty) return 'Set the test username first';
    if (_account == null) return 'No stored account with that username — log in';
    if (s == null) return 'The test account is signed out — log in';
    if (s.username.isEmpty) return "Session's username unknown — guarded steps disabled";
    return _guardOk
        ? 'Stored session is the test account'
        : 'Stored session is "${s.username}" — not the test account';
  }

  // ---------------------------------------------------------------------------
  // D1 — login and session
  // ---------------------------------------------------------------------------

  Future<void> _login() async {
    final login = await DeckboxLoginDialog.show(context);
    if (login == null) return;
    await _reload();
    final session = await SessionStore.load(login.account.id);
    await _record(
      'd1_login',
      _sessionSummary(login.result),
      login.result.page,
      session?.cookies ?? const {},
    );
  }

  /// Run after an app restart: does the stored session still sign in?
  Future<void> _checkSession() => _guarded('d1_check', (client) async {
        final result = await client.checkSession();
        return (
          '${_sessionSummary(result)}\n\n'
              'session saved: ${_session!.savedAt.toIso8601String()}\n'
              'cookie attributes seen on this request:\n'
              '${_attrs(client.cookieAttributes)}',
          result.page,
        );
      });

  /// The app's own *Log out* on the test account.
  Future<void> _forget() async {
    final account = _account;
    if (account == null) return;
    await DeckboxSync.instance.logOut(account);
    await _reload();
    setState(() => _output = 'Test account logged out; its session deleted.');
  }

  // ---------------------------------------------------------------------------
  // D2 — finding the lists
  // ---------------------------------------------------------------------------

  Future<void> _findLists() => _guarded('d2_lists', (client) async {
        final (lists, page) = await client.findLists();
        final kinds = lists.map((l) => l.kind).toSet();
        final missing = [
          for (final k in [
            DeckboxListKind.inventory,
            DeckboxListKind.tradelist,
            DeckboxListKind.wishlist,
          ])
            if (!kinds.contains(k)) k.name,
        ];
        return (
          [
            'lists found: ${lists.length}',
            for (final l in lists) '  $l',
            'missing defaults: ${missing.isEmpty ? 'none' : missing.join(', ')}',
          ].join('\n'),
          page,
        );
      });

  // ---------------------------------------------------------------------------
  // D3 — export and row ids
  // ---------------------------------------------------------------------------

  /// For each list: its page (how rows and their ids are marked up, and
  /// whether it paginates), the export dialog (which extra columns exist) and
  /// the CSV itself, timed. Sequential — one request at a time.
  Future<void> _exports() => _guarded('d3_exports', (client) async {
        final stamp = _stamp();
        final (lists, home) = await client.findLists();
        final lines = <String>[];

        for (final list in lists) {
          final tag = 'd3_${list.kind.name}';
          lines.add('== ${list.name} — /sets/${list.setId}');

          final pageWatch = Stopwatch()..start();
          final page = await client.get('/sets/${list.setId}');
          pageWatch.stop();
          await _write('${stamp}_${tag}_page.html', page.body, client.cookies);
          lines.addAll([
            'page: ${page.status}, ${page.body.length} chars, '
                '${pageWatch.elapsedMilliseconds} ms',
            ..._pageHints(page.body),
          ]);

          final dialog = await client.exportDialog(list.setId);
          await _write('${stamp}_${tag}_dialog.html', dialog.body, client.cookies);
          lines.addAll([
            'export dialog: ${dialog.status}, ${dialog.contentType}',
            '  text: ${_plainText(dialog.body, 900)}',
          ]);

          final csvWatch = Stopwatch()..start();
          final csv = await client.exportCsv(list.setId);
          csvWatch.stop();
          await _write('${stamp}_$tag.csv', csv.body, client.cookies);
          final rows = const LineSplitter().convert(csv.body);
          lines.addAll([
            'csv: ${csv.status}, ${csv.body.length} chars, '
                '${csvWatch.elapsedMilliseconds} ms',
            '  content-type: ${csv.contentType}',
            '  disposition: ${csv.contentDisposition}',
            '  lines: ${rows.length}',
            for (final r in rows.take(4)) '  | $r',
            '',
          ]);
        }
        return (lines.join('\n'), home);
      });

  /// What a list page says about its rows: element ids that look like row
  /// handles, pagination, and the set's own data object.
  static List<String> _pageHints(String html) {
    final rowIds = RegExp(r'''<tr[^>]*\bid=["']([^"']+)["']''')
        .allMatches(html)
        .map((m) => m[1]!)
        .toList();
    final countIds = RegExp(r'''id=["'](card_count_[^"']+)["']''')
        .allMatches(html)
        .map((m) => m[1]!)
        .toList();
    final paging = RegExp(r'pagination|Page \d+ of \d+|next_page|per_page',
            caseSensitive: false)
        .allMatches(html)
        .map((m) => m[0]!)
        .toSet();
    final setData = RegExp(r'Tcg\.set\s*=[^;]{0,400}').firstMatch(html)?[0];
    return [
      '  <tr id=…>: ${rowIds.length}  e.g. ${rowIds.take(5).join(', ')}',
      '  card_count ids: ${countIds.length}  e.g. ${countIds.take(5).join(', ')}',
      '  paging markers: ${paging.isEmpty ? 'none' : paging.join(', ')}',
      '  set data: ${setData ?? '(no Tcg.set = … found)'}',
    ];
  }

  static String _plainText(String html, int max) {
    final t = html
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length > max ? '${t.substring(0, max)}…' : t;
  }

  /// Run 2: for each list and each of two explicit sorts, the list page and
  /// the export side by side — do they agree row for row, on name, printing
  /// and count? Plus the extra columns, and every row id for a stability check
  /// against run 1. Read-only, one request at a time: 12 in all.
  Future<void> _exportsRun2() => _guarded('d3_run2', (client) async {
        final stamp = _stamp();
        final (lists, home) = await client.findLists();
        final lines = <String>[];

        for (final list in lists) {
          for (final sort in const ['n', 'e']) {
            final tag = 'd3r2_${list.kind.name}_$sort';
            final page = await client.listPage(list.setId, sort: sort);
            final csvWatch = Stopwatch()..start();
            final csv = await client.exportCsv(
              list.setId,
              sort: sort,
              columns: 'Scryfall ID,Last Updated',
            );
            csvWatch.stop();
            await _write('${stamp}_${tag}_page.html', page.body, client.cookies);
            await _write('${stamp}_$tag.csv', csv.body, client.cookies);

            final parsed = DeckboxClient.readListPage(page.body);
            final rows = DeckboxCsv.rows(csv.body);
            final header = DeckboxCsv.parse(csv.body).firstOrNull ?? const [];
            lines.addAll([
              '== ${list.name}, sort=$sort — page ${parsed.page}/${parsed.pageCount}, '
                  'size ${parsed.pageSize}; csv ${rows.length} rows, '
                  '${csvWatch.elapsedMilliseconds} ms',
              '  columns: ${header.join(' | ')}',
              ..._compare(list.kind, parsed.rows, rows),
              '',
            ]);
          }
        }
        return (lines.join('\n'), home);
      });

  /// Position by position: page row against export row. The counts compared
  /// are the export's `Count` against the page's own list type (Inventory for
  /// the Tradelist page, whose rows are Inventory rows), and `Tradelist Count`
  /// against the page's Tradelist cell where both exist.
  static List<String> _compare(
    DeckboxListKind kind,
    List<DeckboxPageRow> page,
    List<Map<String, String>> csv,
  ) {
    final countKey = kind == DeckboxListKind.wishlist ? 'Wishlist' : 'Inventory';
    var bad = 0;
    final out = <String>[];
    for (var i = 0; i < page.length || i < csv.length; i++) {
      final p = i < page.length ? page[i] : null;
      final c = i < csv.length ? csv[i] : null;
      final problems = <String>[
        if (p == null || c == null) 'missing on ${p == null ? 'page' : 'export'}',
        if (p != null && c != null && p.name != c['Name']) 'name',
        if (p != null && c != null && (p.printingId ?? '') != (c['Printing Id'] ?? ''))
          'printing',
        if (p != null && c != null && '${p.counts[countKey]}' != c['Count']) 'count',
        if (p != null && c != null && c.containsKey('Tradelist Count') &&
            '${p.counts['Tradelist']}' != c['Tradelist Count'])
          'trade count',
      ];
      if (problems.isNotEmpty) bad++;
      out.add(
        '  ${problems.isEmpty ? 'ok' : 'XX ${problems.join(',')}'} '
        'row ${p?.rowId} ${p?.name ?? c?['Name']} | '
        'scryfall ${c?['Scryfall ID'] ?? '-'} | updated ${c?['Last Updated'] ?? '-'}',
      );
    }
    return ['  rows matching: ${page.length - bad} of ${page.length}', ...out];
  }

  // ---------------------------------------------------------------------------
  // D4 — CSV import  (WRITES to the test account's Inventory)
  // ---------------------------------------------------------------------------

  /// The header of the owner's own collection file, which Deckbox accepted
  /// whole — so the probes vary values, never the format.
  static const _importHeader =
      'Count,Name,Edition Code,Edition,Card Number,Condition,Foil,Language,My Price,Scryfall ID';

  /// One question per file, because **one bad row rejects the whole file** —
  /// a rejection must only ever answer its own question.
  static const _probes = <(String, String, List<String>)>[
    ('p1_good',
        'A new row, plus an exact copy of an existing row. Expect both to land; Massacre Girl 1 → 2',
        [
          '1,Titan Forge,EOC,Edge of Eternities Commander,146,Near Mint,,English,,91a3c3ba-6dbb-454c-86ad-064875382499',
          '1,"Massacre Girl, Most Wanted",FRA,Reality Fracture,234,Near Mint,,English,,9028d31f-9c41-47e3-885b-6a869bca8178',
        ]),
    ('p2_misspelt',
        'Edition name and code both wrong, no Scryfall ID. Expect rejection — how is it reported?',
        ['1,Titan Forge,EOX,Edge of Eternitys Comander,146,Near Mint,,English,,']),
    ('p3_scryfall_vs_edition',
        "Scryfall ID of Canopy Baloth ZNR 304, but the edition says Kaladesh (not in that set). Which wins?",
        ['1,Canopy Baloth,KLD,Kaladesh,304,Near Mint,,English,,d52e90d3-d356-4b23-8f5c-a4004b20394c']),
    ('p4_scryfall_only',
        'Name and Scryfall ID only — no edition, code or number. Enough? (Nissa KLD 163 exists: 1 → 2)',
        ['1,"Nissa, Vital Force",,,,Near Mint,,English,,bbaaa98a-ec40-4ff1-8762-a719cf1c475d']),
    ('p5_old_set_scryfall_code',
        "Fourth Edition by its right name, with Scryfall's code 4ED — Deckbox's own is 4E",
        ['1,Llanowar Elves,4ED,Fourth Edition,261,Near Mint,,English,,']),
    ('p6_etched_as_finish',
        "Aeromoeba MH2 389 with Foil 'etched' and its Scryfall ID",
        ['1,Aeromoeba,MH2,Modern Horizons 2,389,Near Mint,etched,English,,25de0eb6-94f5-440f-8201-cc7dad2f0805']),
    ('p7_etched_as_edition',
        "Aeromoeba as Deckbox's own edition 'Modern Horizons 2 Etched', code MH2_E",
        ['1,Aeromoeba,MH2_E,Modern Horizons 2 Etched,389,Near Mint,,English,,']),
  ];

  Future<void> _importProbes() => _runProbes('d4', _probes);

  /// D9: generic rows — a card with **no printing**, which is how a wishlist
  /// says "any printing will do" (the site's add panel defaults Wishlist to
  /// no printing). Can an import create one, and what does a Scryfall ID do to
  /// it? `w5` is the danger case: re-importing a generic row *exactly as the
  /// export gives it*, stand-in Scryfall ID included — what a backup restore
  /// would send.
  static const _genericProbes = <(String, String, List<String>)>[
    ('w1_name_only',
        'Wishlist: a name and nothing else. Lands generic, picks a printing, or rejected?',
        ['1,Sol Ring,,,,,,,,']),
    ('w2_name_and_attrs',
        'Wishlist: name with condition and language, no printing — like Snake Basket',
        ['1,Lightning Bolt,,,,Played,,Japanese,,']),
    ('w3_name_and_scryfall',
        'Wishlist: name and a Scryfall ID (Titan Forge EOC 146). Expect that exact printing',
        ['1,Titan Forge,,,,,,,,91a3c3ba-6dbb-454c-86ad-064875382499']),
    ('w4_name_only_inventory',
        'Inventory: a name only, with NM English. Generic rows in an Inventory too?',
        ['1,Sol Ring,,,,Near Mint,,English,,']),
    ('w5_export_roundtrip',
        "Wishlist: Gisela's generic row as exported — empty edition, stand-in Scryfall ID "
            '(AVR 209). Generic 1 → 2, or a new AVR row because the ID wins?',
        ['1,"Gisela, Blade of Goldnight",,,,,,,,7208fcb8-83e6-44ce-af9a-ca1566825018']),
  ];

  Future<void> _genericRowProbes() => _runProbes('d9', _genericProbes);

  /// One file per probe, because **one bad row rejects the whole file**. A
  /// probe's target list is in its tag: `…_inventory` goes to Inventory,
  /// everything in a `d9` run otherwise to Wishlist, a `d4` run to Inventory.
  Future<void> _runProbes(
    String run,
    List<(String, String, List<String>)> probes,
  ) async {
    if (!await _confirmWrite('${probes.length} small imports ($run probes)')) return;
    await _guarded('${run}_probes', (client) async {
      final stamp = _stamp();
      final (lists, _) = await client.findLists();
      DeckboxListRef listOf(DeckboxListKind k) => lists.firstWhere((l) => l.kind == k);
      DeckboxListKind targetOf(String tag) => tag.endsWith('_inventory') || run == 'd4'
          ? DeckboxListKind.inventory
          : DeckboxListKind.wishlist;

      final lines = <String>[];
      final touched = <DeckboxListKind>{};
      for (final (tag, question, rows) in probes) {
        final target = listOf(targetOf(tag));
        touched.add(target.kind);
        // Loading the list page first, as the site does, also gives the token.
        await client.listPage(target.setId);
        final csv = [_importHeader, ...rows].join('\r\n');
        lines.addAll([
          '== $tag → ${target.name}',
          '  asks: $question',
          for (final r in rows) '  row: $r',
        ]);
        try {
          final resp = await client.importCsv(target.setId, csv, filename: '$tag.csv');
          await _write('${stamp}_${run}_$tag.response.txt', resp.body, client.cookies);
          lines.addAll([
            '  → ${resp.status}, ${resp.contentType}, ${resp.body.length} chars',
            '  says: ${_plainText(resp.body, 700)}',
          ]);
        } on DeckboxException catch (e) {
          lines.add('  → FAILED: $e');
        }
        lines.add('');
      }

      for (final kind in touched) {
        lines.addAll(await _listSnapshot(client, listOf(kind), stamp, '${run}_after_probes'));
        lines.add('');
      }
      return (lines.join('\n'), (await client.findLists()).$2);
    });
  }

  /// D4b: the owner's own collection file, copied to `deckbox_spike/seed.csv`
  /// over ADB. One upload, then the Inventory export.
  Future<void> _importSeed() async {
    final file = File('$_outDir/seed.csv');
    if (!await file.exists()) {
      setState(() => _output = 'No seed.csv in $_outDir — copy it there first.');
      return;
    }
    final csv = await file.readAsString();
    final rowCount = DeckboxCsv.rows(csv).length;
    if (!await _confirmWrite('one import of $rowCount rows into Inventory')) return;

    await _guarded('d4_seed', (client) async {
      final stamp = _stamp();
      final inventory = await _inventory(client);
      await client.listPage(inventory.setId);

      final watch = Stopwatch()..start();
      final resp = await client.importCsv(inventory.setId, csv, filename: 'seed.csv');
      watch.stop();
      await _write('${stamp}_d4_seed.response.txt', resp.body, client.cookies);
      final lines = [
        'seed: $rowCount rows',
        '  → ${resp.status}, ${resp.contentType}, ${resp.body.length} chars, '
            '${watch.elapsedMilliseconds} ms',
        '  says: ${_plainText(resp.body, 1500)}',
        '',
        ...await _listSnapshot(client, inventory, stamp, 'd4_after_seed'),
      ];
      return (lines.join('\n'), (await client.findLists()).$2);
    });
  }

  // ---------------------------------------------------------------------------
  // D5 / D8 — removing, lowering, trade counts  (WRITES)
  // ---------------------------------------------------------------------------

  /// What makes an export row a row — the identity removals point at (D3).
  static String _identity(Map<String, String> r) => const [
        'Name', 'Printing Id', 'Condition', 'Language', 'Foil', 'Signed',
        'Artist Proof', 'Altered Art', 'Misprint', 'Promo', 'Textless',
      ].map((k) => r[k] ?? '').join('|');

  static int _count(Map<String, String>? r, [String key = 'Count']) =>
      int.tryParse(r?[key] ?? '') ?? 0;

  /// The first row the test may safely act on: a real printing, nothing for
  /// trade, and an identity no other row shares — so "before" and "after" can
  /// only ever mean that one row.
  static int? _pick(
    List<Map<String, String>> rows,
    Map<String, int> identities,
    bool Function(int i, Map<String, String> r) test,
  ) {
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if ((r['Printing Id'] ?? '').isEmpty || _count(r, 'Tradelist Count') != 0) continue;
      if (identities[_identity(r)] != 1) continue;
      if (test(i, r)) return i;
    }
    return null;
  }

  static Map<String, int> _identityCounts(List<Map<String, String>> rows) {
    final m = <String, int>{};
    for (final r in rows) {
      m.update(_identity(r), (n) => n + 1, ifAbsent: () => 1);
    }
    return m;
  }

  /// The row with this identity in a fresh export, or null if it is gone.
  static Map<String, String>? _find(List<Map<String, String>> rows, String identity) {
    for (final r in rows) {
      if (_identity(r) == identity) return r;
    }
    return null;
  }

  Future<List<Map<String, String>>> _exportRows(DeckboxClient c, DeckboxListRef l) async =>
      DeckboxCsv.rows((await c.exportCsv(l.setId)).body);

  /// D5: batch-remove two rows on two different pages, lower one row through
  /// `update_count` (timed), and try the decks-only batch on a detailed set.
  Future<void> _d5() async {
    if (!await _confirmWrite('D5: remove 2 rows, lower 2 counts in Inventory')) return;
    await _guarded('d5', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final before = await _exportRows(client, inv);
      final ids = _identityCounts(before);
      final lines = <String>['Inventory before: ${before.length} rows'];

      final a = _pick(before, ids, (i, r) => i < 30 && _count(r) == 1);
      final b = _pick(before, ids, (i, r) => i >= 30 && i < 60 && _count(r) == 1);
      final l = _pick(before, ids, (i, r) => _count(r) >= 2);
      final x = _pick(before, ids, (i, r) => i != l && _count(r) >= 2);
      if (a == null || b == null || l == null) {
        throw const DeckboxException('d5', 'no suitable rows — needs 60+ rows and a count of 2+');
      }
      String show(int i) =>
          '#$i ${before[i]['Name']} (${before[i]['Edition Code']}) ×${before[i]['Count']}';
      lines.add('targets: remove ${show(a)} [page 1] and ${show(b)} [page 2]; '
          'lower ${show(l)}${x == null ? '' : '; decks-batch ${show(x)}'}');

      // The push-time lookup, for real.
      final watchLocate = Stopwatch()..start();
      final rowIds = await client.locateRows(inv, before, [a, b, l, ?x]);
      watchLocate.stop();
      lines.add('located ${rowIds.length} rows in ${watchLocate.elapsedMilliseconds} ms: $rowIds');

      // 1. One batch remove, across two pages.
      final rm = await client.removeRows(inv, [rowIds[a]!, rowIds[b]!]);
      await _write('${stamp}_d5_remove.response.txt', rm.body, client.cookies);
      lines.add('remove → ${rm.status}, ${rm.body.length} chars: ${_plainText(rm.body, 160)}');

      // 2. Lower one row by one, timed; then three no-op repeats for an average.
      final newCount = _count(before[l]) - 1;
      final times = <int>[];
      for (var k = 0; k < 4; k++) {
        final w = Stopwatch()..start();
        final up = await client.updateCount(
          setId: inv.setId, rowId: rowIds[l]!, count: newCount, viewingSetId: inv.setId);
        w.stop();
        times.add(w.elapsedMilliseconds);
        if (k == 0) {
          await _write('${stamp}_d5_update_count.response.txt', up.body, client.cookies);
          lines.add('update_count → ${up.status}, ${up.body.length} chars: '
              '${_plainText(up.body, 160)}');
        }
      }
      lines.add('update_count times (ms): $times');

      // 3. The decks' batch, once, on a detailed set.
      if (x != null) {
        try {
          final cs = await client.post('/cards_sets/count', {
            'set_id': '${inv.setId}',
            'ids': '[${rowIds[x]}]',
            'counts': '[${_count(before[x]) - 1}]',
            'with_inventory': '0',
          }, referer: '/sets/${inv.setId}');
          await _write('${stamp}_d5_cards_sets_count.response.txt', cs.body, client.cookies);
          lines.add('cards_sets/count → ${cs.status}, ${cs.body.length} chars: '
              '${_plainText(cs.body, 160)}');
        } on DeckboxException catch (e) {
          lines.add('cards_sets/count → FAILED: $e');
        }
      }

      // 4. What actually changed.
      final after = await _exportRows(client, inv);
      String state(int i) {
        final r = _find(after, _identity(before[i]));
        return r == null ? 'GONE' : '×${r['Count']}';
      }
      lines.addAll([
        'Inventory after: ${after.length} rows (${before.length - after.length} fewer)',
        '  removed page-1 row: ${state(a)}   removed page-2 row: ${state(b)}',
        '  lowered row: ${before[l]['Count']} → ${state(l)} (asked $newCount)',
        if (x != null) '  decks-batch row: ${before[x]['Count']} → ${state(x)} (asked ${_count(before[x]) - 1})',
      ]);
      return (lines.join('\n'), home);
    });
  }

  /// D8: trade counts through `update_count` with the Tradelist's set id, the
  /// clamping the site's JavaScript describes, and what removing a row *from
  /// the Tradelist* does to the Inventory row behind it.
  Future<void> _d8() async {
    if (!await _confirmWrite('D8: four trade-count steps on one Inventory row')) return;
    await _guarded('d8', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final trade = lists.firstWhere((l) => l.kind == DeckboxListKind.tradelist);
      final before = await _exportRows(client, inv);
      final t = _pick(before, _identityCounts(before), (i, r) => i < 30 && _count(r) == 1);
      if (t == null) throw const DeckboxException('d8', 'no single-copy row on page 1');
      final id = _identity(before[t]);
      final rowId = (await client.locateRows(inv, before, [t]))[t]!;
      final lines = <String>[
        'row: ${before[t]['Name']} (${before[t]['Edition Code']}) — id $rowId, owned 1, for trade 0',
      ];

      Future<void> step(String what, Future<DeckboxPage> Function() send) async {
        final resp = await send();
        await _write('${stamp}_d8_${lines.length}.response.txt', resp.body, client.cookies);
        final r = _find(await _exportRows(client, inv), id);
        final inTrade = _find(await _exportRows(client, trade), id);
        lines.add('$what → ${resp.status}: '
            '${r == null ? 'GONE from Inventory' : 'owned ${r['Count']}, for trade ${r['Tradelist Count']}'}'
            '; on Tradelist: ${inTrade == null ? 'no' : 'yes'}');
      }

      await step('1. trade count → 1', () => client.updateCount(
          setId: trade.setId, rowId: rowId, count: 1, viewingSetId: inv.setId));
      await step('2. trade count → 2 (more than owned)', () => client.updateCount(
          setId: trade.setId, rowId: rowId, count: 2, viewingSetId: inv.setId));
      await step('3. owned → 1', () => client.updateCount(
          setId: inv.setId, rowId: rowId, count: 1, viewingSetId: inv.setId));
      await step('4. remove the row from the Tradelist', () => client.removeRows(trade, [rowId]));
      return (lines.join('\n'), home);
    });
  }

  // ---------------------------------------------------------------------------
  // T — Tradelist additions  (WRITES)
  // ---------------------------------------------------------------------------

  /// The Tradelist probes (2026-10-19): what an import does to the Tradelist
  /// and the Inventory behind it, one row each, on rows picked from the test
  /// account's own Inventory.
  ///
  /// - **T1** Inventory import of an exact variant already owned: added to the
  ///   row, or a second row?
  /// - **T2** Tradelist import of a card not owned: Inventory row created, with
  ///   a trade count?
  /// - **T3** Tradelist import of an exact variant owned once, none for trade:
  ///   marks that copy, adds a copy, or refused?
  /// - **T4** Inventory import with a `Tradelist Count` column, card not owned:
  ///   does the import carry the trade count?
  ///
  /// **Second set** — can one Inventory import set trade counts on rows that
  /// already exist, for a bulk *mark for trade* in one request?
  ///
  /// - **T5** `Count 1` + `Tradelist Count 1` on a row owned once, none for
  ///   trade: 2 owned and 1 for trade, or something else?
  /// - **T6** `Count 0` + `Tradelist Count 1` on such a row: refused, or the
  ///   copy marked without adding one?
  /// - **T7** `Count 0` + `Tradelist Count 1` on a row already all for trade:
  ///   does the trade count **add** (→ 2, owned raised) or **replace** (stays)?
  Future<void> _tradelistProbes({bool second = false}) async {
    final what = second ? '3 one-row Inventory imports (T5–T7)' : '4 one-row imports (T1–T4) into Inventory and Tradelist';
    if (!await _confirmWrite(what)) return;
    await _guarded(second ? 't2_probes' : 't_probes', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final trade = lists.firstWhere((l) => l.kind == DeckboxListKind.tradelist);
      Future<List<Map<String, String>>> export(DeckboxListRef l) async =>
          DeckboxCsv.rows((await client.exportCsv(l.setId, columns: 'Scryfall ID,Last Updated')).body);

      final before = await export(inv);
      final owned = {for (final r in before) r['Scryfall ID'] ?? ''};
      final perPrinting = <String, int>{};
      for (final r in before) {
        perPrinting[r['Scryfall ID'] ?? ''] = (perPrinting[r['Scryfall ID'] ?? ''] ?? 0) + 1;
      }
      bool plain(Map<String, String> r) =>
          r['Count'] == '1' &&
          (r['Tradelist Count'] ?? '0') == '0' &&
          (r['Printing Id'] ?? '').isNotEmpty &&
          (r['Scryfall ID'] ?? '').isNotEmpty &&
          (r['Foil'] ?? '').isEmpty &&
          perPrinting[r['Scryfall ID']] == 1 &&
          DeckboxMapping.flagColumns.every((f) => (r[f] ?? '').isEmpty);
      final plainRows = before.where(plain).toList();
      if (plainRows.length < 2) throw const DeckboxException('t', 'needs two plain single-copy rows');
      // A row whose every copy is for trade — what T4 leaves behind.
      final allTraded = before
          .where((r) =>
              (int.tryParse(r['Tradelist Count'] ?? '') ?? 0) >= 1 &&
              r['Tradelist Count'] == r['Count'] &&
              (r['Scryfall ID'] ?? '').isNotEmpty &&
              (r['Foil'] ?? '').isEmpty &&
              perPrinting[r['Scryfall ID']] == 1)
          .firstOrNull;
      if (second && allTraded == null) throw const DeckboxException('t', 'needs a row with every copy for trade — run T1–T4 first');

      // Two printings the Inventory has no row of at all.
      final cards = CardsDatabase.instance;
      final notOwned = <({String id, String name})>[];
      for (final name in const ['Llanowar Elves', 'Counterspell', 'Giant Growth', 'Shock', 'Opt', 'Divination']) {
        for (final c in await cards.printingsOf(name)) {
          if (!owned.contains(c.id) && c.lang == 'en') {
            notOwned.add((id: c.id, name: c.name));
            break;
          }
        }
        if (notOwned.length == 2) break;
      }
      if (notOwned.length < 2) throw const DeckboxException('t', 'no unowned printings found in the card cache');

      String q(String v) => v.contains(RegExp(r'[",]')) ? '"${v.replaceAll('"', '""')}"' : v;
      String csv(List<String> header, List<String> row) =>
          [header.map(q).join(','), row.map(q).join(',')].join('\r\n');
      const header = ['Count', 'Name', 'Condition', 'Language', 'Foil', 'Scryfall ID'];
      List<String> ownedRow(Map<String, String> r) =>
          ['1', r['Name']!, r['Condition'] ?? 'Near Mint', r['Language'] ?? 'English', '', r['Scryfall ID']!];
      List<String> newRow(({String id, String name}) c) => ['1', c.name, 'Near Mint', 'English', '', c.id];

      List<String> countRow(Map<String, String> r, int count, int trade) => [
            '$count', r['Name']!, r['Condition'] ?? 'Near Mint', r['Language'] ?? 'English', '', r['Scryfall ID']!, '$trade',
          ];
      final withTrade = [...header, 'Tradelist Count'];

      final probes = second
          ? <(String, String, DeckboxListRef, String, String)>[
              ('T5', 'Inventory import, Count 1 + Tradelist Count 1, row owned once, none for trade: 2 owned / 1 for trade?',
                  inv, csv(withTrade, countRow(plainRows[0], 1, 1)), plainRows[0]['Scryfall ID']!),
              ('T6', 'Inventory import, Count 0 + Tradelist Count 1, row owned once, none for trade: refused, or marked?',
                  inv, csv(withTrade, countRow(plainRows[1], 0, 1)), plainRows[1]['Scryfall ID']!),
              ('T7', 'Inventory import, Count 0 + Tradelist Count 1, row all for trade: does trade add, or replace?',
                  inv, csv(withTrade, countRow(allTraded!, 0, 1)), allTraded['Scryfall ID']!),
            ]
          : <(String, String, DeckboxListRef, String, String)>[
        ('T1', 'Inventory import, exact variant owned once: added to the row, or a second row?',
            inv, csv(header, ownedRow(plainRows[0])), plainRows[0]['Scryfall ID']!),
        ('T2', 'Tradelist import, card not owned: Inventory row created, with a trade count?',
            trade, csv(header, newRow(notOwned[0])), notOwned[0].id),
        ('T3', 'Tradelist import, exact variant owned once and none for trade: mark, add, or refuse?',
            trade, csv(header, ownedRow(plainRows[1])), plainRows[1]['Scryfall ID']!),
        ('T4', 'Inventory import with a Tradelist Count of 1, card not owned: does it carry?',
            inv, csv([...header, 'Tradelist Count'], [...newRow(notOwned[1]), '1']), notOwned[1].id),
      ];

      String rowsOf(List<Map<String, String>> rows, String scry) {
        final mine = rows.where((r) => r['Scryfall ID'] == scry).toList();
        if (mine.isEmpty) return 'no row';
        final each = mine.map((r) => '${r['Count']}× ${r['Condition']} ${r['Language']} '
            'trade ${r['Tradelist Count'] ?? '-'} [${r['Printing Id']}]');
        return '${mine.length} row(s): ${each.join('; ')}';
      }

      final lines = <String>[];
      for (final (tag, question, target, body, scry) in probes) {
        final invBefore = await export(inv);
        final tradeBefore = await export(trade);
        await client.listPage(target.setId); // as the site does — and the token
        lines.addAll(['== $tag → ${target.name}', '  asks: $question', '  sent:', for (final l in body.split('\r\n')) '    $l']);
        try {
          final resp = await client.importCsv(target.setId, body, filename: '$tag.csv');
          await _write('${stamp}_t_$tag.response.txt', resp.body, client.cookies);
          lines.add('  → ${resp.status}: ${_plainText(resp.body, 300)}');
        } on DeckboxException catch (e) {
          lines.add('  → FAILED: $e');
        }
        final invAfter = await export(inv);
        final tradeAfter = await export(trade);
        lines.addAll([
          '  Inventory  before: ${rowsOf(invBefore, scry)}',
          '             after:  ${rowsOf(invAfter, scry)}   (${invBefore.length} → ${invAfter.length} rows)',
          '  Tradelist  before: ${rowsOf(tradeBefore, scry)}',
          '             after:  ${rowsOf(tradeAfter, scry)}   (${tradeBefore.length} → ${tradeAfter.length} rows)',
          '',
        ]);
        if (mounted) setState(() => _output = lines.join('\n'));
      }
      return (lines.join('\n'), home);
    });
  }

  /// **T8** — does an Inventory import's `Tradelist Count` **add** to a row's
  /// trade count, or **replace** it? (T7 meant to ask, but Deckbox refuses a
  /// count of 0.) Self-contained: T8a adds a card whose **name** has no row at
  /// all in the Inventory — 1 owned, 1 for trade — and T8b sends the same row
  /// again. 2 / 2 means it adds; 2 / 1 means it replaces.
  Future<void> _tradeCountProbe() async {
    if (!await _confirmWrite('2 one-row Inventory imports (T8a, T8b) of a card not owned')) return;
    await _guarded('t8_probe', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final trade = lists.firstWhere((l) => l.kind == DeckboxListKind.tradelist);
      Future<List<Map<String, String>>> export(DeckboxListRef l) async =>
          DeckboxCsv.rows((await client.exportCsv(l.setId, columns: 'Scryfall ID,Last Updated')).body);

      // A card the Inventory has no row of under any printing — not in the
      // seed, not left over from earlier probes.
      final names = {for (final r in await export(inv)) r['Name']};
      ({String id, String name})? pick;
      for (final name in const ['Storm Crow', 'Grizzly Bears', 'Goblin Piker', 'Wind Drake', 'Gray Ogre', 'Scathe Zombies']) {
        if (names.contains(name)) continue;
        final printings = [for (final c in await CardsDatabase.instance.printingsOf(name)) if (c.lang == 'en') c];
        if (printings.isNotEmpty) {
          pick = (id: printings.first.id, name: name);
          break;
        }
      }
      if (pick == null) throw const DeckboxException('t8', 'every candidate card already has a row');

      const body = 'Count,Name,Condition,Language,Foil,Scryfall ID,Tradelist Count';
      final csv = '$body\r\n1,${pick.name},Near Mint,English,,${pick.id},1';
      String rowsOf(List<Map<String, String>> rows) {
        final mine = rows.where((r) => r['Scryfall ID'] == pick!.id).toList();
        if (mine.isEmpty) return 'no row';
        return '${mine.length} row(s): ${mine.map((r) => '${r['Count']} owned, ${r['Tradelist Count']} for trade').join('; ')}';
      }

      final lines = <String>['card: ${pick.name} (${pick.id}) — no row of that name before', ''];
      for (final tag in const ['T8a', 'T8b']) {
        await client.listPage(inv.setId);
        lines.addAll(['== $tag → Inventory', '  sent: ${csv.replaceAll('\r\n', ' | ')}']);
        try {
          final resp = await client.importCsv(inv.setId, csv, filename: '$tag.csv');
          await _write('${stamp}_t_$tag.response.txt', resp.body, client.cookies);
          lines.add('  → ${resp.status}: ${_plainText(resp.body, 200)}');
        } on DeckboxException catch (e) {
          lines.add('  → FAILED: $e');
        }
        lines.addAll([
          '  Inventory after: ${rowsOf(await export(inv))}',
          '  Tradelist after: ${rowsOf(await export(trade))}',
          '',
        ]);
        if (mounted) setState(() => _output = lines.join('\n'));
      }
      lines.add('T8b reading: 2 owned / 2 for trade = Tradelist Count ADDS; 2 / 1 = it REPLACES');
      return (lines.join('\n'), home);
    });
  }

  /// **T9** — one Inventory file mixing additions flagged for trade with ones
  /// that are not: the shape a push takes when some staged additions are
  /// flagged *Also up for trade* and some are not. Untested until now — every
  /// earlier file had the *Tradelist Count* column on all rows or none.
  ///
  /// Self-contained. **Setup:** eight cards with no row of their name in the
  /// Inventory; four imported plainly (no trade column — the tested shape),
  /// giving four known rows owned once, none for trade. Then two mixed files,
  /// each with an existing row flagged and unflagged, and a new card flagged
  /// and unflagged:
  ///
  /// - **T9a** unflagged rows carry `0`
  /// - **T9b** unflagged rows carry an **empty** cell
  ///
  /// Expected: existing flagged 2/1, existing unflagged 2/0, new flagged 1/1,
  /// new unflagged 1/0 (owned / for trade).
  Future<void> _mixedTradeProbe() async {
    if (!await _confirmWrite('3 Inventory imports (T9 setup, T9a, T9b) of 8 cards not owned')) return;
    await _guarded('t9_probe', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final trade = lists.firstWhere((l) => l.kind == DeckboxListKind.tradelist);
      Future<List<Map<String, String>>> export(DeckboxListRef l) async =>
          DeckboxCsv.rows((await client.exportCsv(l.setId, columns: 'Scryfall ID,Last Updated')).body);

      // Eight cards with no row of their name — known to start at nothing.
      final names = {for (final r in await export(inv)) r['Name']};
      final picks = <({String id, String name})>[];
      for (final name in const [
        'Grizzly Bears', 'Goblin Piker', 'Wind Drake', 'Gray Ogre', 'Scathe Zombies',
        'Coral Eel', 'Raging Goblin', 'Hill Giant', 'Merfolk of the Pearl Trident',
        'Fugitive Wizard', 'Horned Turtle', 'Craw Wurm', 'Feral Shadow', 'Durkwood Boars',
        'Bog Imp', 'Pikemen', 'Ironroot Treefolk', 'Giant Octopus',
      ]) {
        if (names.contains(name)) continue;
        final en = [for (final c in await CardsDatabase.instance.printingsOf(name)) if (c.lang == 'en') c];
        if (en.isEmpty) continue;
        picks.add((id: en.first.id, name: name));
        if (picks.length == 8) break;
      }
      if (picks.length < 8) throw DeckboxException('t9', 'found only ${picks.length} of 8 cards with no row');

      String q(String v) => v.contains(RegExp(r'[",]')) ? '"${v.replaceAll('"', '""')}"' : v;
      String row(({String id, String name}) c, String? trade) =>
          ['1', q(c.name), 'Near Mint', 'English', '', c.id, ?trade].join(',');
      const plainHeader = 'Count,Name,Condition,Language,Foil,Scryfall ID';
      const tradeHeader = '$plainHeader,Tradelist Count';

      String state(List<Map<String, String>> rows, String id) {
        final mine = rows.where((r) => r['Scryfall ID'] == id).toList();
        if (mine.isEmpty) return 'no row';
        return mine.map((r) => '${r['Count']}/${r['Tradelist Count'] ?? '-'}').join(' + ');
      }

      final lines = <String>['cards: ${picks.map((c) => c.name).join(', ')}', ''];
      Future<void> send(String tag, DeckboxListRef target, String header, List<String> rows,
          List<(String, ({String id, String name}), String)> expect) async {
        final invBefore = await export(inv);
        final tradeBefore = await export(trade);
        final csv = [header, ...rows].join('\r\n');
        await client.listPage(target.setId);
        lines.addAll(['== $tag → ${target.name}', '  sent:', for (final l in csv.split('\r\n')) '    $l']);
        try {
          final resp = await client.importCsv(target.setId, csv, filename: '$tag.csv');
          await _write('${stamp}_t_$tag.response.txt', resp.body, client.cookies);
          lines.add('  → ${resp.status}: ${_plainText(resp.body, 300)}');
        } on DeckboxException catch (e) {
          lines.add('  → FAILED: $e');
        }
        final invAfter = await export(inv);
        final tradeAfter = await export(trade);
        lines.add('  owned/for trade — Inventory before → after | Tradelist after | expected');
        for (final (what, c, expected) in expect) {
          final got = state(invAfter, c.id);
          lines.add('  ${got == expected ? 'OK ' : '!! '} $what ${c.name}: '
              '${state(invBefore, c.id)} → $got | ${state(tradeAfter, c.id)} | $expected');
        }
        lines.add('  (Inventory ${invBefore.length} → ${invAfter.length} rows, '
            'Tradelist ${tradeBefore.length} → ${tradeAfter.length})');
        lines.add('');
        if (mounted) setState(() => _output = lines.join('\n'));
      }

      // Setup: four rows owned once, none for trade — the tested shape.
      await send('T9-setup', inv, plainHeader, [for (final i in [0, 1, 4, 5]) row(picks[i], null)], [
        for (final i in [0, 1, 4, 5]) ('setup', picks[i], '1/0'),
      ]);

      await send('T9a', inv, tradeHeader, [
        row(picks[0], '1'), row(picks[1], '0'), row(picks[2], '1'), row(picks[3], '0'),
      ], [
        ('existing, flagged  ', picks[0], '2/1'),
        ('existing, unflagged', picks[1], '2/0'),
        ('new, flagged       ', picks[2], '1/1'),
        ('new, unflagged     ', picks[3], '1/0'),
      ]);

      await send('T9b', inv, tradeHeader, [
        row(picks[4], '1'), row(picks[5], ''), row(picks[6], '1'), row(picks[7], ''),
      ], [
        ('existing, flagged  ', picks[4], '2/1'),
        ('existing, unflagged', picks[5], '2/0'),
        ('new, flagged       ', picks[6], '1/1'),
        ('new, unflagged     ', picks[7], '1/0'),
      ]);

      lines.add('Reading: every line OK in T9a → one file with 0 works; in T9b → one file with empty cells works.');
      return (lines.join('\n'), home);
    });
  }

  /// **E1–E7** — Deckbox's own row edit, `update_single` (mirror_editing.md).
  /// The counts are always sent back as the panel read them: amounts stay with
  /// staging.
  ///
  /// Self-contained. **Setup:** one card with no row of its name, imported in
  /// two printings — **A** 3 owned / 1 for trade, **B** 1 / 1. Then, on A:
  ///
  /// - **E1** open both panels: ids, values, the edition list
  /// - **E2** condition → Good (LP), language → German
  /// - **E5** flags: signed on, then foil on beside it, then both off
  /// - **E3** a printing not owned
  /// - **E4** into B's exact variant (B's printing, NM, English, no flags) —
  ///   the merge: which row survives, do both counts add
  /// - **E7** an edition id of **another** card — what a refusal looks like
  ///
  /// After each save: the reply, both rows in the export, and the row's panel
  /// opened again **by its old id** — the id kept or not.
  Future<void> _editProbes() async {
    if (!await _confirmWrite('E: 1 setup import (2 rows of a card not owned), then 7 row saves on them')) return;
    await _guarded('e_probe', (client) async {
      final stamp = _stamp();
      final (lists, home) = await client.findLists();
      final inv = lists.firstWhere((l) => l.kind == DeckboxListKind.inventory);
      final trade = lists.firstWhere((l) => l.kind == DeckboxListKind.tradelist);
      Future<List<Map<String, String>>> export(DeckboxListRef l) async =>
          DeckboxCsv.rows((await client.exportCsv(l.setId, columns: 'Scryfall ID,Last Updated')).body);

      // A card with no row of its name, in two plain printings — oldest
      // first, so neither is too new for Deckbox.
      final before = await export(inv);
      final names = {for (final r in before) r['Name']};
      ({String name, String a, String b})? pick;
      for (final name in const [
        'Shock', 'Giant Growth', 'Naturalize', 'Duress', 'Cancel', 'Unsummon',
        'Terror', 'Disfigure', 'Mind Rot', 'Negate', 'Plummet', 'Essence Scatter',
      ]) {
        if (names.contains(name)) continue;
        final plain = [
          for (final c in (await CardsDatabase.instance.printingsOf(name)).reversed)
            if (c.lang == 'en' && c.setCode.length == 3 && RegExp(r'^\d+$').hasMatch(c.collectorNumber)) c,
        ];
        final second = plain.skip(1).where((c) => c.setCode != plain.first.setCode).firstOrNull;
        if (second != null) {
          pick = (name: name, a: plain.first.id, b: second.id);
          break;
        }
      }
      if (pick == null) throw const DeckboxException('e', 'every candidate card already has a row');
      final card = pick;

      final lines = <String>['card: ${card.name} — A ${card.a}, B ${card.b}', ''];
      void show() {
        if (mounted) setState(() => _output = lines.join('\n'));
      }

      String state(List<Map<String, String>> rows) {
        final mine = rows.where((r) => r['Name'] == card.name).toList();
        if (mine.isEmpty) return 'no row';
        return mine
            .map((r) => '${r['Edition Code']} #${r['Card Number']} ${r['Count']}/${r['Tradelist Count'] ?? '-'} '
                '${r['Condition']} ${r['Language']}${(r['Foil'] ?? '').isEmpty ? '' : ' foil'}'
                '${(r['Signed'] ?? '').isEmpty ? '' : ' signed'}')
            .join('  +  ');
      }

      String describe(DeckboxRowPanel p) => 'row ${p.rowId} · card ${p.cardId} · set ${p.setId} · '
          '${p.count}/${p.tradeCount ?? '-'} · ${p.edition ?? 'edition ${p.editionId}'} · '
          'cond ${p.conditionId} · lang ${p.languageId} · flags [${p.flags.join(',')}] · tags [${p.tagIds ?? '-'}]';

      Future<DeckboxRowPanel?> panel(String rowId, String tag) async {
        final page = await client.rowPanel(rowId, viewingSetId: inv.setId);
        await _write('${stamp}_e_${tag}_panel_$rowId.html', page.body, client.cookies);
        try {
          final p = DeckboxRowPanel.parse(page.body);
          lines.add('  panel $rowId: ${describe(p)}');
          return p;
        } on FormatException catch (e) {
          lines.add('  panel $rowId: ${page.status}, unreadable — ${e.message}: ${_plainText(page.body, 160)}');
          return null;
        }
      }

      Future<DeckboxRowPanel?> save(String tag, String what, DeckboxRowPanel p, String data,
          {List<String> reopen = const []}) async {
        lines.addAll(['== $tag — $what', '  sent: $data']);
        try {
          final reply = await client.saveRow(setId: p.setId, data: data, viewingSetId: inv.setId);
          await _write('${stamp}_e_$tag.response.txt', reply.body, client.cookies);
          final redrew = reply.body.contains("Element.update('show_detailed_contents'");
          lines.add('  → ${reply.status}, ${reply.body.length} chars: '
              '${redrew ? "Element.update('show_detailed_contents', …)" : _plainText(reply.body, 300)}');
        } on DeckboxException catch (e) {
          lines.add('  → FAILED: $e');
        }
        lines.add('  Inventory: ${state(await export(inv))}');
        lines.add('  Tradelist: ${state(await export(trade))}');
        DeckboxRowPanel? again;
        for (final id in [p.rowId, ...reopen]) {
          final r = await panel(id, tag);
          if (id == p.rowId) again = r;
        }
        lines.add('');
        show();
        return again;
      }

      // Setup: A 3 owned / 1 for trade, B 1 / 1.
      const header = 'Count,Name,Condition,Language,Foil,Scryfall ID,Tradelist Count';
      final csv = [header, '3,${card.name},Near Mint,English,,${card.a},1', '1,${card.name},Near Mint,English,,${card.b},1']
          .join('\r\n');
      await client.listPage(inv.setId);
      final reply = await client.importCsv(inv.setId, csv, filename: 'E-setup.csv');
      await _write('${stamp}_e_setup.response.txt', reply.body, client.cookies);
      final setup = await export(inv);
      lines.addAll(['== setup', '  Inventory: ${state(setup)}', '']);
      int indexOf(String id) => setup.indexWhere((r) => r['Scryfall ID'] == id);
      final (ia, ib) = (indexOf(card.a), indexOf(card.b));
      if (ia < 0 || ib < 0) throw DeckboxException('e', 'setup did not land: ${_plainText(reply.body, 200)}');
      final ids = await client.locateRows(inv, setup, [ia, ib]);
      final (rowA, rowB) = (ids[ia]!, ids[ib]!);
      show();

      lines.add('== E1 — open both panels');
      var a = await panel(rowA, 'E1');
      final b = await panel(rowB, 'E1');
      if (a == null || b == null) return (lines.join('\n'), home);
      lines.add('  editions of ${card.name}: ${a.editions.length}');
      for (final e in a.editions.take(12)) {
        lines.add('    ${e.id}: $e');
      }
      lines.add('');
      show();

      a = await save('E2', 'condition → Good (LP), language → German', a, a.saveData(conditionId: 3, languageId: 2));
      if (a == null) return (lines.join('\n'), home);
      a = await save('E5a', 'signed on', a, a.saveData(flags: [...a.flags, 'is_signed']));
      if (a == null) return (lines.join('\n'), home);
      a = await save('E5b', 'foil on beside it', a, a.saveData(flags: [...a.flags, 'is_foil']));
      if (a == null) return (lines.join('\n'), home);
      a = await save('E5c', 'both off', a, a.saveData(flags: const []));
      if (a == null) return (lines.join('\n'), home);

      final other = a.editions.where((e) => e.id != 0 && e.id != a!.editionId && e.id != b.editionId).toList();
      final target = other.where((e) => !e.code.contains('_') && RegExp(r'^\d+$').hasMatch(e.number)).firstOrNull ??
          other.firstOrNull;
      if (target == null) {
        lines.addAll(['== E3 — skipped: no third printing in the list', '']);
      } else {
        a = await save('E3', 'a printing not owned: $target', a, a.saveData(editionId: target.id));
        if (a == null) return (lines.join('\n'), home);
      }

      final merged = await save(
        'E4',
        "into B's variant: ${b.edition}, NM, English, no flags",
        a,
        a.saveData(editionId: b.editionId, conditionId: 2, languageId: 1, flags: const []),
        reopen: [rowB],
      );

      // Another card's edition — from a row of a different name, read only.
      final otherRow = setup.indexWhere((r) => r['Name'] != card.name && (r['Scryfall ID'] ?? '').isNotEmpty);
      final survivor = merged ?? await panel(rowB, 'E7');
      if (otherRow < 0 || survivor == null) {
        lines.add('== E7 — skipped: ${otherRow < 0 ? 'no other card' : 'no row left to save'}');
      } else {
        final otherId = (await client.locateRows(inv, setup, [otherRow]))[otherRow]!;
        lines.add('== E7 — the edition of ${setup[otherRow]['Name']} (row $otherId)');
        final o = await panel(otherId, 'E7');
        if (o != null) {
          await save('E7', "another card's edition: ${o.edition}", survivor, survivor.saveData(editionId: o.editionId));
        }
      }

      lines.add('Reading: E2/E3/E5 — row id kept when the panel reopens by the old id with the new values; '
          'E4 — which id reopens, and the counts (4/2 = both add); E7 — the refusal, or what it did.');
      return (lines.join('\n'), home);
    });
  }

  /// **E8** — a Wishlist row's edit panel, **read only**: does it open by row
  /// id, and does it read as an Inventory panel does (no trade count; tags?).
  /// Nothing is saved.
  Future<void> _wishlistPanelProbe() => _guarded('e8_wishlist_panel', (client) async {
        final stamp = _stamp();
        final (lists, home) = await client.findLists();
        final wish = lists.firstWhere((l) => l.kind == DeckboxListKind.wishlist);
        final rows = DeckboxCsv.rows((await client.exportCsv(wish.setId, columns: 'Scryfall ID,Last Updated')).body);
        if (rows.isEmpty) throw const DeckboxException('e8', 'the Wishlist is empty — add a card to it first');
        final lines = <String>['Wishlist: ${rows.length} rows', ''];

        // The first row, and one with a printing if the first has none.
        final picks = {0, rows.indexWhere((r) => (r['Printing Id'] ?? '').isNotEmpty)}..remove(-1);
        await client.listPage(wish.setId);
        final ids = await client.locateRows(wish, rows, picks);
        for (final i in picks) {
          final r = rows[i];
          lines.add('== ${r['Name']} · ${r['Edition']} #${r['Card Number']} · ${r['Count']}× · '
              '${r['Condition']} ${r['Language']} ${r['Foil']}');
          final page = await client.rowPanel(ids[i]!, viewingSetId: wish.setId);
          await _write('${stamp}_e8_panel_${ids[i]}.html', page.body, client.cookies);
          try {
            final p = DeckboxRowPanel.parse(page.body);
            lines.addAll([
              '  row ${p.rowId} · card ${p.cardId} · set ${p.setId} (Wishlist is ${wish.setId}) · '
                  'count ${p.count} · trade ${p.tradeCount ?? '(none)'} · ${p.edition ?? 'edition ${p.editionId}'} · '
                  'cond ${p.conditionId} · lang ${p.languageId} · flags [${p.flags.join(',')}] · '
                  'tags ${p.tagIds == null ? '(none)' : '[${p.tagIds}]'} · price ${p.price ?? '(none)'}',
              '  editions listed: ${p.editions.length}',
              '  would send: ${p.saveData()}',
            ]);
          } on FormatException catch (e) {
            lines.add('  ${page.status}, unreadable — ${e.message}: ${_plainText(page.body, 300)}');
          }
          lines.add('');
        }
        return (lines.join('\n'), home);
      });

  // ---------------------------------------------------------------------------
  // M3 — the push engine  (WRITES)
  // ---------------------------------------------------------------------------

  /// M3 step 1: stages a few additions and removals on the test account's
  /// Inventory through the app's own staging, and pushes them through
  /// [DeckboxSync.push] — the one write path the app has. Deckbox's own trade
  /// feature is never touched. One of each kind of change:
  ///
  /// - a whole row removed, from page 2 when there is one (the page lookup)
  /// - a count lowered by one
  /// - a printing already there added in *Played* (by Scryfall ID)
  /// - a generic *Sol Ring* (by name only)
  /// - a made-up card name, which Deckbox should refuse — so the rest are
  ///   sent a second time
  /// - etched outside Deckbox's etched editions, refused before upload
  Future<void> _m3PushTest() async {
    final account = _account;
    if (account == null || !_guardOk) return;
    if (!await _confirmWrite('M3: stage test changes on Inventory and push them')) return;

    final lines = <String>[];
    void show(String line) {
      lines.add(line);
      if (mounted) setState(() => _output = lines.join('\n'));
    }

    setState(() => _busy = true);
    try {
      final dao = CollectionDatabase.instance.externalDao;
      final inv = (await dao.listsFor(account.id)).firstWhere(
        (l) => l.kind == 'inventory',
        orElse: () => throw const DeckboxException('m3', 'no Inventory in the lists folder'),
      );
      show('Pulling ${inv.name}…');
      final pulled = await DeckboxSync.instance.pull(inv);
      if (pulled is! Pulled) {
        throw DeckboxException('m3', 'pull: ${pulled is PullFailed ? pulled.message : pulled.runtimeType}');
      }
      final list = (await dao.listById(inv.id))!;
      final before = await dao.watchEntries(list.id).first;

      final seen = <String, int>{};
      for (final e in before) {
        seen[e.identityKey] = (seen[e.identityKey] ?? 0) + 1;
      }
      bool plain(ExternalEntry e) =>
          seen[e.identityKey] == 1 && !e.anyPrinting && e.cardId != null;
      final remove = before.where((e) => plain(e) && e.position >= 30 && e.count == 1).firstOrNull ??
          before.where((e) => plain(e) && e.count == 1).firstOrNull;
      final lower = before.where((e) => plain(e) && e.count >= 2 && e != remove).firstOrNull;
      final printing = before
          .where((e) =>
              plain(e) &&
              e != remove &&
              e != lower &&
              e.finish == DeckboxMapping.nonfoil &&
              e.conditionCode != 2)
          .firstOrNull;
      if (remove == null || lower == null || printing == null) {
        throw const DeckboxException('m3', 'no suitable rows — import seed.csv first');
      }
      String row(ExternalEntry e) => '#${e.position} ${e.name} (${e.editionCode}) ×${e.count}';

      final already = await dao.stagedFor(list.id);
      if (already.isNotEmpty) show('${already.length} already staged — pushed along with the rest');
      await dao.stageRemoval(list: list, row: remove);
      await dao.stageRemoval(list: list, row: lower);
      await dao.stageAddition(
        listId: list.id,
        name: printing.name,
        cardId: printing.cardId,
        cardRef: printing.cardRef,
        anyPrinting: false,
        finish: printing.finish,
        languageCode: printing.languageCode,
        conditionCode: 2,
        setCode: printing.editionCode.toLowerCase(),
        setName: printing.edition,
        collectorNumber: printing.cardNumber,
      );
      for (final name in const ['Sol Ring', 'Homunculus Push Test']) {
        await dao.stageAddition(
          listId: list.id,
          name: name,
          cardId: null,
          cardRef: null,
          anyPrinting: true,
          finish: null,
          languageCode: null,
          conditionCode: null,
        );
      }
      await dao.stageAddition(
        listId: list.id,
        name: 'Etched test (never sent)',
        cardId: 'not-a-card',
        cardRef: null,
        anyPrinting: false,
        finish: DeckboxMapping.etched,
        languageCode: 'en',
        conditionCode: 0,
        setCode: 'cmr',
        setName: 'Commander Legends',
        collectorNumber: '0',
      );
      show('Staged: remove ${row(remove)}; lower ${row(lower)} by 1; '
          'add ${printing.name} (${printing.editionCode}) in Played, a generic Sol Ring, '
          'a made-up name, a CMR etched');
      show('');

      final watch = Stopwatch()..start();
      final report = await DeckboxSync.instance.push(list, onStep: (s) => show('  · $s'));
      watch.stop();

      final after = await dao.watchEntries(list.id).first;
      int copies(bool Function(ExternalEntry) where) =>
          after.where(where).fold(0, (n, e) => n + e.count);
      int copiesBefore(bool Function(ExternalEntry) where) =>
          before.where(where).fold(0, (n, e) => n + e.count);
      bool isPlayed(ExternalEntry e) => e.cardId == printing.cardId && e.conditionCode == 2;
      bool isSolRing(ExternalEntry e) => e.anyPrinting && e.name == 'Sol Ring';
      final left = await dao.stagedFor(list.id);

      show('');
      show('in ${watch.elapsedMilliseconds} ms — removed ${report.removed}, lowered ${report.lowered}, '
          'added ${report.added}, refused ${report.refused}, skipped ${report.skipped}');
      show('stopped: ${report.stoppedAt ?? 'no — ran to the end'}');
      show('');
      show('On Deckbox now (${before.length} → ${after.length} rows):');
      show('  removed row: ${after.any((e) => e.identityKey == remove.identityKey) ? 'STILL THERE' : 'gone'}');
      show('  lowered row: ${lower.count} → '
          '${after.where((e) => e.identityKey == lower.identityKey).firstOrNull?.count ?? 'GONE'}');
      show('  ${printing.name} in Played: ${copiesBefore(isPlayed)} → ${copies(isPlayed)}');
      show('  generic Sol Ring: ${copiesBefore(isSolRing)} → ${copies(isSolRing)}');
      show('  made-up name: ${after.any((e) => e.name == 'Homunculus Push Test') ? 'LANDED' : 'not there'}');
      show('');
      show('Still staged: ${left.length}');
      for (final s in left) {
        show('  ${s.direction} ${s.quantity}× ${s.name}'
            '${s.flag == null ? '' : ' [${s.flag}]'}'
            '${s.sentAt == null ? '' : ' [sent, expecting ${s.expectedCount}]'}'
            ' — ${s.lastError ?? 'no error'}');
      }
    } on DeckboxException catch (e) {
      show('FAILED — $e');
    } catch (e) {
      AppLogger.w('Deckbox spike m3 failed: ${e.runtimeType}');
      show('FAILED — ${e.runtimeType}');
    } finally {
      await _reload();
      final cookies = _session?.cookies ?? const <String, String>{};
      await _write('${_stamp()}_m3_push.txt', lines.join('\n'), cookies);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Local only: drops everything staged on the test account's lists, so the
  /// next test starts clean. Sends nothing.
  Future<void> _unstageAll() async {
    final account = _account;
    if (account == null) return;
    final dao = CollectionDatabase.instance.externalDao;
    var n = 0;
    for (final l in await dao.listsFor(account.id)) {
      final ids = [for (final s in await dao.stagedFor(l.id)) s.id];
      n += ids.length;
      await dao.unstage(ids);
    }
    setState(() => _output = 'Unstaged $n changes. Nothing was sent.');
  }

  // ---------------------------------------------------------------------------
  // Test-account reset  (WRITES — removes every row of one list)
  // ---------------------------------------------------------------------------

  /// Empties one list, to keep later test results readable.
  ///
  /// **Deliberately not in [DeckboxClient].** The app must never be able to
  /// wipe a list — wipe-and-reimport is rejected in the plan — so the request
  /// lives only here, behind the account guard, a fresh row count and a typed
  /// confirmation. It is the site's own *select all → Remove*: a detailed set's
  /// `/detailed_cards_sets/remove` with **neither `cards` nor `f`**, which the
  /// site's code reads as "every row in the set".
  Future<void> _removeAll(DeckboxListKind kind) async {
    final session = _session;
    if (session == null || !_guardOk) return;

    // Count first, on a client of its own, so the confirmation states a fact.
    final peek = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
    DeckboxListRef list;
    int rows;
    try {
      final (lists, _) = await peek.findLists();
      list = lists.firstWhere((l) => l.kind == kind);
      rows = DeckboxCsv.rows((await peek.exportCsv(list.setId)).body).length;
    } catch (e) {
      setState(() => _output = 'FAILED before removing — ${e.runtimeType}: $e');
      return;
    } finally {
      peek.close();
    }
    if (!mounted || !await _confirmTyped(list.name, rows)) return;

    await _guarded('reset_${kind.name}', (client) async {
      final stamp = _stamp();
      await client.listPage(list.setId); // the site posts from the list page
      final resp = await client.post(
        '/detailed_cards_sets/remove',
        {
          'set_id': '${list.setId}',
          // Tcg.set.data.type.underscore() — "Inventory" → "inventory".
          'render_context_name': kind.name,
        },
        referer: '/sets/${list.setId}',
      );
      await _write('${stamp}_reset_${kind.name}.response.txt', resp.body, client.cookies);
      final after = DeckboxCsv.rows((await client.exportCsv(list.setId)).body).length;
      return (
        [
          'removed all from ${list.name}: $rows rows before, $after after',
          '  → ${resp.status}, ${resp.contentType}, ${resp.body.length} chars',
          '  says: ${_plainText(resp.body, 500)}',
        ].join('\n'),
        resp,
      );
    });
  }

  /// "Type the list's name to confirm" — a tap is too cheap for this one.
  Future<bool> _confirmTyped(String listName, int rows) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TypedConfirmDialog(
        listName: listName,
        message: 'All $rows rows of $listName on "${_session?.username}". '
            'Type the list name to confirm.',
      ),
    );
    return ok ?? false;
  }

  Future<DeckboxListRef> _inventory(DeckboxClient client) async {
    final (lists, _) = await client.findLists();
    return lists.firstWhere(
      (l) => l.kind == DeckboxListKind.inventory,
      orElse: () => throw const DeckboxException('import', 'no Inventory list found'),
    );
  }

  /// A list's export after a write, saved whole, summarised in lines. An
  /// empty `Printing Id` is shown as `[any printing]` — the export still gives
  /// such a row a stand-in Scryfall ID (D3), so the ID alone would mislead.
  Future<List<String>> _listSnapshot(
    DeckboxClient client,
    DeckboxListRef list,
    String stamp,
    String tag,
  ) async {
    final watch = Stopwatch()..start();
    final csv = await client.exportCsv(list.setId, columns: 'Scryfall ID,Last Updated');
    watch.stop();
    await _write('${stamp}_${tag}_${list.kind.name}.csv', csv.body, client.cookies);
    final rows = DeckboxCsv.rows(csv.body);
    return [
      '${list.name} now: ${rows.length} rows, export ${csv.body.length} chars in '
          '${watch.elapsedMilliseconds} ms',
      for (final r in rows.take(40))
        '  ${r['Count']}× ${r['Name']} | '
            '${(r['Printing Id'] ?? '').isEmpty ? '[any printing]' : '${r['Edition']} (${r['Edition Code']}) #${r['Card Number']}'} | '
            '${r['Condition']} ${r['Language']} ${r['Foil']} | ${r['Scryfall ID']}',
      if (rows.length > 40) '  … ${rows.length - 40} more in the saved CSV',
    ];
  }

  /// Every write asks first, and names the account it writes to.
  Future<bool> _confirmWrite(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write to Deckbox?'),
        content: Text('$what, on "${_session?.username}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write')),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  static String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  /// An extra record file for a step, redacted like the rest.
  Future<void> _write(
    String name,
    String content,
    Map<String, String> cookies,
  ) async {
    final redactor = DeckboxClient(cookies: cookies);
    final dir = Directory(_outDir);
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsString(redactor.redact(content));
    redactor.close();
  }

  /// Runs a step on the stored session — only if the guard passes — records
  /// what it returns, and saves the session's refreshed cookies.
  ///
  /// **Refreshed cookies are saved back** because Deckbox reissues
  /// `_tcg_session` on every response with a new six-month expiry (D1). Keeping
  /// only the cookie from login would let the session lapse six months after
  /// login however often it is used.
  Future<void> _guarded(
    String step,
    Future<(String, DeckboxPage)> Function(DeckboxClient client) body,
  ) async {
    final session = _session;
    final account = _account;
    if (session == null || account == null || !_guardOk) return;

    setState(() => _busy = true);
    final client = DeckboxClient(cookies: session.cookies, onLog: AppLogger.d);
    try {
      final (summary, page) = await body(client);
      final refreshed = session.withCookies(client.cookies);
      await SessionStore.save(account.id, refreshed);
      _session = refreshed;
      await _record(step, summary, page, client.cookies);
    } on DeckboxException catch (e) {
      AppLogger.w('$e');
      setState(() => _output = 'FAILED — $e');
    } catch (e) {
      AppLogger.w('Deckbox spike step $step failed: ${e.runtimeType}');
      setState(() => _output = 'FAILED — ${e.runtimeType}');
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Writes `<stamp>_<step>.txt` (the summary plus the redirect chain) and
  /// `.html` (the final page), both redacted with the cookies the step held.
  Future<void> _record(
    String step,
    String summary,
    DeckboxPage page,
    Map<String, String> cookies,
  ) async {
    final redactor = DeckboxClient(cookies: cookies);
    final now = DateTime.now();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final text = [
      '$step — ${now.toIso8601String()}',
      summary,
      '',
      'final: ${page.status} ${page.url}',
      'chain:',
      for (final hop in page.hops) hop.toString(),
      '',
      'cookies held (names only): ${cookies.keys.join(', ')}',
    ].join('\n');

    final dir = Directory(_outDir);
    await dir.create(recursive: true);
    await File('${dir.path}/${stamp}_$step.txt')
        .writeAsString(redactor.redact(text));
    await File('${dir.path}/${stamp}_$step.html')
        .writeAsString(redactor.redact(page.body));
    redactor.close();

    if (mounted) setState(() => _output = redactor.redact(text));
  }

  static String _sessionSummary(DeckboxLoginResult r) =>
      'state: ${r.state.name}\n'
      'username read from page: ${r.username ?? '(none found)'}';

  static String _attrs(Map<String, String> a) => a.isEmpty
      ? '  (none — no Set-Cookie on this request)'
      : a.entries.map((e) => '  ${e.key}: ${e.value}').join('\n');

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final canGuarded = !_busy && _guardOk;

    return Scaffold(
      appBar: AppBar(title: const Text('Deckbox spike')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Account guard', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _testUser,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Test account username',
                helperText: 'Guarded steps run only on this account',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) async {
                await DevFlags.setDeckboxTestUser(v);
                await _reload();
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                _guardOk ? Icons.verified_user_outlined : Icons.block_outlined,
                size: 18,
                color: _guardOk ? Colors.green : theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(_guardText)),
            ]),
            const Divider(height: 32),

            Text('Stored session', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              s == null
                  ? 'None'
                  : 'username: ${s.username.isEmpty ? '(unknown)' : s.username}\n'
                      'saved: ${s.savedAt}\n'
                      'cookies: ${s.cookies.keys.join(', ')}',
              style: mono,
            ),
            const Divider(height: 32),

            Text('D1 — Login and session', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                onPressed: _busy ? null : _login,
                child: const Text('Log in…'),
              ),
              OutlinedButton(
                onPressed: canGuarded ? _checkSession : null,
                child: const Text('Check stored session'),
              ),
              TextButton(
                onPressed: _busy || s == null ? null : _forget,
                child: const Text('Forget session'),
              ),
            ]),
            const Divider(height: 32),

            Text('D2 — Finding the lists', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: canGuarded ? _findLists : null,
                child: const Text('Find lists'),
              ),
            ]),
            const Divider(height: 32),

            Text('D3 — Exports and row ids', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: canGuarded ? _exports : null,
                child: const Text('Run 1: export all three'),
              ),
              FilledButton.tonal(
                onPressed: canGuarded ? _exportsRun2 : null,
                child: const Text('Run 2: compare page and export'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Read-only. Run 2: both sorts, extra columns, row by row.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('D4 — CSV import  (writes)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _importProbes : null,
                child: Text('D4a: ${_probes.length} probes'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _importSeed : null,
                child: const Text('D4b: import seed.csv'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _genericRowProbes : null,
                child: Text('D9: ${_genericProbes.length} generic-row probes'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              "Each asks first. Into the test account's Inventory only.",
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('D5 / D8 — Removing, lowering, trade counts  (writes)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _d5 : null,
                child: const Text('D5: remove + lower'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _d8 : null,
                child: const Text('D8: trade counts'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Needs the seeded Inventory (60+ rows). Each asks first.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('T — Tradelist probes  (writes)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? () => _tradelistProbes() : null,
                child: const Text('T1–T4: Tradelist imports'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? () => _tradelistProbes(second: true) : null,
                child: const Text('T5–T7: trade counts by import'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _tradeCountProbe : null,
                child: const Text('T8: does Tradelist Count add?'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _mixedTradeProbe : null,
                child: const Text('T9: mixed trade flags in one file'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Four one-row imports into Inventory and Tradelist; records both lists before and after each.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('E — Row edits  (writes)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _editProbes : null,
                child: const Text('E1–E7: edit a row in place'),
              ),
              OutlinedButton(
                onPressed: canGuarded ? _wishlistPanelProbe : null,
                child: const Text('E8: Wishlist panel (read only)'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Imports one card in two printings, then saves one row seven times; counts untouched.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('M3 — Push engine  (writes)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: canGuarded ? _m3PushTest : null,
                child: const Text('Stage test changes + push'),
              ),
              TextButton(
                onPressed: _busy || _account == null ? null : _unstageAll,
                child: const Text('Unstage all'),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Inventory, through the app\'s own push. Needs the seeded Inventory. '
              'Unstage all sends nothing.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            Text('Reset the test account  (removes everything)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final kind in const [
                DeckboxListKind.inventory,
                DeckboxListKind.tradelist,
                DeckboxListKind.wishlist,
              ])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: canGuarded ? () => _removeAll(kind) : null,
                  child: Text('Empty ${kind.name}'),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Counts the rows, then asks you to type the list name.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),

            if (_busy) const LinearProgressIndicator(),
            SelectableText(_output, style: mono),
            const SizedBox(height: 12),
            Text('Records: $_outDir', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The typed confirmation for emptying a list.
///
/// **Owns its controller.** The first version made the controller in the
/// caller and disposed it the moment `showDialog` returned — but the dialog is
/// still on screen then, animating out, and its field touched the disposed
/// controller. In a debug build that assertion stopped the debugger mid-tap
/// (2026-10-15). Here the controller dies with the dialog's own state.
class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({required this.listName, required this.message});

  final String listName;
  final String message;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _typed.text == widget.listName;
    return AlertDialog(
      title: Text('Remove all of ${widget.listName}?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.message),
        const SizedBox(height: 12),
        TextField(
          controller: _typed,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: widget.listName,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Remove all'),
        ),
      ],
    );
  }
}
