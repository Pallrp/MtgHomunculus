import 'package:flutter/material.dart';

import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../services/dhash.dart';
import '../theme/picker_tokens.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// What the app knows about its copy of Scryfall, and how to refresh it.
///
/// **Status and two verbs, not settings.** Nothing here is a preference, which
/// is why it is reached from a row in the lists folder rather than a gear — see
/// `local_data_store.md` → The card data screen.
///
/// The two verbs differ in a way worth keeping straight:
///
/// | | Does | Can |
/// | Update | writes rows by primary key | add and replace, never remove |
/// | Re-download | deletes both files, re-runs setup | clear withdrawn printings |
///
/// Update is therefore safe to leave running; Re-download blocks, because it
/// starts by deleting the database this screen is describing.
class CardDataScreen extends StatefulWidget {
  final CardsDatabase db;

  /// Clear `bulk_imported_at` and leave, which sends the shell back through
  /// first-run setup — the blocking, full-screen path Re-download wants and
  /// which already exists.
  final Future<void> Function() onReDownload;

  const CardDataScreen({
    super.key,
    required this.db,
    required this.onReDownload,
  });

  @override
  State<CardDataScreen> createState() => _CardDataScreenState();
}

class _CardDataScreenState extends State<CardDataScreen> {
  CardDataCounts? _counts;
  int? _dbBytes;
  String _updatedAt = '';
  String _importedAt = '';

  int? _hashEntries;
  String? _hashVersion;

  /// Null while still being counted. It needs every id in the index plus every
  /// hashable id in the table, so it is the one figure here that cannot be a
  /// cheap `COUNT(*)` — the rest of the panel renders without waiting for it.
  int? _notYetHashed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await widget.db.counts();
    final bytes = await CardsDatabase.fileSize();
    final updated = await widget.db.metaValue(MetaKeys.bulkUpdatedAt) ?? '';
    final imported = await widget.db.metaValue(MetaKeys.bulkImportedAt) ?? '';
    if (!mounted) return;
    setState(() {
      _counts = counts;
      _dbBytes = bytes;
      _updatedAt = updated;
      _importedAt = imported;
    });

    // Index second: it is the slow half, and the panel above is already legible
    // without it.
    final index = await HashIndex.load();
    if (!mounted) return;
    setState(() {
      _hashEntries = index?.count;
      _hashVersion = index == null ? null : DHash.version;
    });

    if (index == null) {
      if (mounted) setState(() => _notYetHashed = null);
      return;
    }
    final indexed = index.ids();
    final hashable = await widget.db.hashableIds();
    if (!mounted) return;
    setState(() => _notYetHashed =
        hashable.where((id) => !indexed.contains(id)).length);
  }

  // ---------------------------------------------------------------------------
  // Re-download
  // ---------------------------------------------------------------------------

  Future<void> _confirmReDownload() async {
    final t = PickerTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-download card data?'),
        // The confirm has one job: say what is kept. In an app holding someone's
        // collection, a destructive-looking button reads as "delete my cards".
        content: const Text(
          'This deletes the downloaded card database and the match index, then '
          'downloads them again (~78 MB).\n\n'
          'Your lists and collection are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.vermilion),
            child: const Text('Re-download'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onReDownload();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final c = _counts;

    return Scaffold(
      backgroundColor: t.ground,
      appBar: AppBar(title: const Text('Card data')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _Group(children: [
            _Row(label: 'Cards', value: _thousands(c?.cards)),
            _Row(label: 'Unique names', value: _thousands(c?.uniqueNames)),
            _Row(label: 'Sets', value: _thousands(c?.sets)),
            _Row(label: 'Hash entries', value: _thousands(_hashEntries)),
            _Row(
              label: 'Not yet hashed',
              value: _hashEntries == null && _notYetHashed == null
                  ? 'no index'
                  : _thousands(_notYetHashed),
              // The row that earns its place: it is the gap between the card
              // table and the index, and the answer to "why did the scanner not
              // recognise this card" — a printing newer than the last index
              // build, still falling through to OCR.
              attention: (_notYetHashed ?? 0) > 0,
            ),
          ]),
          _Group(children: [
            _Row(label: 'Bulk data updated', value: _date(_updatedAt)),
            _Row(label: 'Imported', value: _date(_importedAt)),
            _Row(label: 'Hash version', value: _hashVersion ?? '—'),
            _Row(label: 'Database size', value: _megabytes(_dbBytes)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: OutlinedButton.icon(
              onPressed: _confirmReDownload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.vermilion,
                side: BorderSide(color: t.vermilion),
                minimumSize: const Size.fromHeight(46),
              ),
              label: const Text('Re-download card data'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static String _thousands(int? n) {
    if (n == null) return '…';
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// `2026-08-24` → `24 Aug`. Returns the raw value if it will not parse — a
  /// date that cannot be formatted is still more useful shown than hidden.
  static String _date(String iso) {
    if (iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day} ${_months[d.month - 1]}';
  }

  static String _megabytes(int? bytes) => bytes == null
      ? '—'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// One block of rows, separated from the next by the rule the artifact draws
/// between *what is in there now* and *where it came from*.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool attention;

  const _Row({
    required this.label,
    required this.value,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: t.textDim),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: PickerTokens.mono(context, size: 13).copyWith(
              color: attention ? t.warning : t.text,
              fontWeight: attention ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
