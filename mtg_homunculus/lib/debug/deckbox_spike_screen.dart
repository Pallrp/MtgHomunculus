import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../features/card_lookup/data/collection_database.dart';
import '../features/card_lookup/external/deckbox/deckbox_client.dart';
import '../features/card_lookup/external/deckbox/deckbox_csv.dart';
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
