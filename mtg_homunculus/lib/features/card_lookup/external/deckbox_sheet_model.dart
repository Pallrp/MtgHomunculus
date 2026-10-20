import '../data/collection_database.dart';
import 'external_dao.dart';

/// Where a scan goes — the radio on a staged section's header.
enum ScanTarget {
  add('To add'),
  remove('To remove');

  const ScanTarget(this.label);
  final String label;
}

/// A staged addition and the mirrored row it adds to, if any.
typedef StagedAddition = ({StagedChange staged, ExternalEntry? existing});

/// A staged removal and the mirrored row it removes from — null once that row
/// is gone from Deckbox.
typedef StagedRemoval = ({StagedChange staged, ExternalEntry? row});

/// What a Deckbox list's sheet shows, worked out from the mirror and what is
/// staged: the three sections, and the pills that tie them together.
///
/// | Pill     | Means                                                          |
/// | -------- | -------------------------------------------------------------- |
/// | `x2`     | a **new row** on Deckbox — no exact variant match in the mirror |
/// | `+2`     | **adds to an existing row** — same printing and variant        |
/// | `−2 of 3`| a removal, against the row's current count                     |
///
/// **The flip from `x2` to `+2` is the double-count cue:** a pull that brings
/// in a card also staged turns its row from `x2` to `+2`.
class DeckboxSheetModel {
  DeckboxSheetModel({
    required this.list,
    required List<ExternalEntry> mirror,
    required List<StagedChange> staged,
    String query = '',
  }) {
    final rows = tradelist ? [for (final e in mirror) if (e.tradeCount > 0) e] : mirror;
    final byIdentity = <String, ExternalEntry>{};
    for (final e in rows) {
      byIdentity.putIfAbsent(e.identityKey, () => e);
    }
    // A Tradelist addition marks an Inventory row — any of them, including
    // one with nothing for trade yet, which the Tradelist does not show.
    final anyRow = <String, ExternalEntry>{};
    for (final e in mirror) {
      anyRow.putIfAbsent(e.identityKey, () => e);
    }

    // Newest first: the top of a staged section is the card just staged.
    final ordered = [...staged]..sort((a, b) => b.stagedAt.compareTo(a.stagedAt));
    for (final s in ordered) {
      if (s.direction == 'add') {
        final existing = tradelist ? anyRow[s.identityKey] : rows.where((e) => addsTo(s, e)).firstOrNull;
        additions.add((staged: s, existing: existing));
        if (existing != null) added[existing.id] = (added[existing.id] ?? 0) + s.quantity;
      } else {
        final row = byIdentity[s.identityKey];
        removals.add((staged: s, row: row));
        if (row != null) removed[row.id] = (removed[row.id] ?? 0) + s.quantity;
      }
    }
    copies = rows.fold(0, (n, e) => n + ExternalDao.countOn(list, e));
    unique = rows.length;

    final q = query.trim().toLowerCase();
    bool hit(String name, String set) =>
        q.isEmpty || name.toLowerCase().contains(q) || set.toLowerCase().contains(q);
    onDeckbox = [for (final e in rows) if (hit(e.name, e.editionCode)) e];
    additions.retainWhere((a) => hit(a.staged.name, a.staged.setCode));
    removals.retainWhere((r) => hit(r.staged.name, r.staged.setCode));
  }

  final ExternalList list;

  bool get tradelist => list.kind == 'tradelist';

  final additions = <StagedAddition>[];
  final removals = <StagedRemoval>[];

  /// The mirror as this list shows it — a Tradelist only its rows for trade —
  /// filtered by the search.
  late final List<ExternalEntry> onDeckbox;

  /// Staged copies per mirrored row id, each way — the small pills beside a
  /// row's count.
  final added = <int, int>{};
  final removed = <int, int>{};

  /// The whole list on Deckbox, unfiltered.
  late final int copies;
  late final int unique;

  int countOn(ExternalEntry row) => ExternalDao.countOn(list, row);

  /// What a push would send: every change not flagged. (Only a Tradelist's
  /// additions — marks — and removals are ever flagged.)
  int get sendable =>
      additions.where((a) => a.staged.flag == null).length + removals.where((r) => r.staged.flag == null).length;

  int get flagged =>
      additions.where((a) => a.staged.flag != null).length + removals.where((r) => r.staged.flag != null).length;

  /// How many copies a Tradelist addition may mark on its row: the free ones.
  /// Null anywhere else, or when the row is gone.
  int? markCap(StagedAddition a) => tradelist && a.existing != null ? ExternalDao.freeOf(a.existing!) : null;

  /// Whether a staged addition lands on this mirrored row rather than making a
  /// new one: the same printing — or, generic, the same card — in exactly the
  /// same finish, language and condition, on a plain row. A blank attribute
  /// matches only a blank one: Deckbox keeps a generic with no condition as a
  /// row of its own (M3 device test, 2026-10-15).
  static bool addsTo(StagedChange s, ExternalEntry e) =>
      e.rowFlags.isEmpty &&
      e.condition != 'Proxy' &&
      (s.anyPrinting ? e.anyPrinting && e.name == s.name : !e.anyPrinting && e.cardId == s.cardId) &&
      e.finish == s.finish &&
      e.languageCode == s.languageCode &&
      e.conditionCode == s.conditionCode;

  /// The pill for a staged addition: `xN` a new row, `+N` onto an existing
  /// one. On a Tradelist the row always exists — it is a mark — so `+N` means
  /// the row is already partly for trade, and `xN` that it is new on the
  /// Tradelist.
  String additionPill(StagedAddition a) {
    final n = a.staged.quantity;
    final onto = tradelist ? (a.existing?.tradeCount ?? 0) > 0 : a.existing != null;
    return onto ? '+$n' : 'x$n';
  }

  /// The Tradelist's half of an Inventory addition's pill, when it is also
  /// going up for trade: `+N` onto a row already partly for trade, else `xN`
  /// — new on the Tradelist. Null when not for trade.
  String? tradeHalf(StagedAddition a) {
    if (list.kind != 'inventory' || !a.staged.forTrade) return null;
    final n = a.staged.quantity;
    return (a.existing?.tradeCount ?? 0) > 0 ? '+$n' : 'x$n';
  }

  /// The pill for a staged removal — or, flagged, what is wrong.
  String removalPill(StagedRemoval r) {
    final flag = r.staged.flag;
    if (flag == 'gone' || r.row == null) return 'gone';
    if (flag == 'ambiguous') return '2 rows';
    return '−${r.staged.quantity} of ${countOn(r.row!)}';
  }

  /// A flagged removal, in words.
  static String? flagText(StagedChange s) => switch (s.flag) {
        null => null,
        'gone' => 'No longer on Deckbox — not sent',
        'unmatched' => 'Not tied to an Inventory row — unstage it and add it again',
        'ambiguous' => 'Two rows on Deckbox match — not sent',
        final f when f.startsWith('short:') && s.direction == 'add' =>
          'Only ${f.substring(6)} not yet for trade now — not sent',
        final f when f.startsWith('short:') =>
          'Deckbox has only ${f.substring(6)} now — not sent',
        final f => f,
      };
}
