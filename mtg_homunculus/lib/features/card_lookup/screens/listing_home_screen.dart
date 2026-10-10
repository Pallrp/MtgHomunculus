import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../data/hash_index.dart';
import '../models/dev_flags.dart';
import '../models/scan_defaults.dart';
import '../services/card_data_updater.dart';
import '../theme/picker_tokens.dart';
import 'card_data_screen.dart';
import 'card_data_setup_screen.dart';
import 'listing_detail_screen.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Entry point for the Card Lookup sub-app.
///
/// Shows every list and lets the user create, open, or delete them.  Camera
/// permission is requested here so the dialog fires once, up-front — not
/// mid-drag or mid-scan.
class ListingHomeScreen extends StatefulWidget {
  const ListingHomeScreen({super.key});

  @override
  State<ListingHomeScreen> createState() => _ListingHomeScreenState();
}

class _ListingHomeScreenState extends State<ListingHomeScreen> {
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  List<CardList>   _listings     = [];
  Map<int, ({int copies, int unique})> _counts = const {};
  bool             _loading      = true;

  /// For the card data row and the screen behind it. Null until first needed.
  CardsDatabase get _cards => CardsDatabase.instance;

  int?    _cardCount;
  String  _bulkUpdatedAt = '';

  CollectionDatabase get _db => CollectionDatabase.instance;

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _requestCamera();
    _load();
  }

  Future<void> _loadCardData() async {
    try {
      final count = await _cards.cardCount();
      final updated = await _cards.metaValue(MetaKeys.bulkUpdatedAt) ?? '';
      if (!mounted) return;
      setState(() {
        _cardCount = count;
        _bulkUpdatedAt = updated;
      });
    } catch (_) {
      // The row degrades to its label alone. Not worth a message: the screen
      // behind it reports properly.
    }
  }

  Future<void> _openCardData() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CardDataScreen(db: _cards, onReDownload: _reDownload),
      ),
    );
    if (mounted) unawaited(_loadCardData());
  }

  /// Clear the import marker and delete the index, then hand over to the
  /// blocking setup screen — the same path first run takes, so there is no
  /// separate recovery flow to maintain.
  Future<void> _reDownload() async {
    await _cards.setMeta(MetaKeys.bulkImportedAt, '');
    try {
      final f = await HashIndex.file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (!mounted) return;

    // Removes both this screen and the card data screen above it: there is
    // nothing to go back to while the database is empty.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (ctx) => CardDataSetupScreen(
          db: _cards,
          onReady: () => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute(builder: (_) => const ListingHomeScreen()),
          ),
        ),
      ),
      (r) => r.isFirst,
    );
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _cameraStatus = status);
  }

  Future<void> _load() async {
    // Loaded here because this screen is the only way into the sub-app, and
    // every surface below it renders chips against these.
    await ScanDefaults.loadCurrent();
    await DevFlags.load();

    // Card data row: both figures are cheap, and the row is meant to be legible
    // without a tap — the count and the age are what you want at the moment a
    // scan has just failed on a card you know exists.
    unawaited(_loadCardData());

    // Restores the badge from `meta` and runs the weekly ETag check if it is
    // due. Here because this screen is the only way into the sub-app and the
    // row that reports the result is on it. A failed check says nothing and
    // does not advance the date.
    unawaited(CardDataUpdater.instance.refresh());

    final listings = await _db.allLists();
    final counts   = await _db.countsForAll();
    if (mounted) {
      setState(() {
        _listings = listings;
        _counts   = counts;
        _loading  = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Push [ListingDetailScreen] and reload the index on return (card count
  /// may have changed while scanning).
  Future<void> _openListing(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailScreen(listId: id)),
    );
    _load();
  }

  /// Show the "New listing" dialog.  On confirm, create the listing and open it.
  Future<void> _showCreateDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateListingDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final list = await _db.createList(name);
    await _openListing(list.id);
  }

  /// Optimistically remove the list from the UI, then delete it.
  ///
  /// The default list refuses to delete, so it is put straight back rather than
  /// vanishing from the screen while surviving in the database.
  Future<void> _deleteListing(CardList list) async {
    setState(() => _listings.removeWhere((e) => e.id == list.id));
    final gone = await _db.deleteList(list.id);
    if (!mounted) return;
    if (!gone) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:  Text('The scan list cannot be deleted'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:  Text('Listing deleted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Card Lookup'),
      ),
      // Lifted clear of the card data row, which is pinned to the bottom —
      // otherwise the FAB lands on top of it and eats the chevron.
      floatingActionButtonLocation:
          const _EndFloatAbove(_CardDataRow.height),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        tooltip:   'New listing',
        child:     const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Camera-permission warning — shown when the user denied the prompt.
        // Scanning will silently fail when they reach ListingDetailScreen;
        // this banner tells them why and offers a path to fix it.
        if (!_cameraStatus.isGranted)
          _CameraWarningBanner(
            status:         _cameraStatus,
            onOpenSettings: openAppSettings,
          ),

        // Listing content.
        Expanded(
          child: _listings.isEmpty ? _buildEmptyState() : _buildList(),
        ),

        // Card data — pinned below the lists, never scrolling with them. It is
        // infrastructure, not a list, and it is deliberately a row rather than a
        // gear: a gear promises options to configure, and this has a status and
        // two actions. See local_data_store.md.
        ListenableBuilder(
          listenable: CardDataUpdater.instance,
          builder: (context, _) => _CardDataRow(
            cardCount: _cardCount,
            updatedAt: _bulkUpdatedAt,
            updateAvailable: CardDataUpdater.instance.updateAvailable,
            updating:
                CardDataUpdater.instance.phase == UpdatePhase.running,
            onTap: _openCardData,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_outlined,
            size:  64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text(
            'No listings yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to create your first listing',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount:        _listings.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final entry = _listings[index];
        // The default list has no delete action at all — swiping it would only
        // be refused, and offering a gesture that never works is worse than
        // omitting it.
        if (entry.isDefault) {
          return _ListingRow(
            entry: entry,
            counts: _counts[entry.id],
            onTap: () => _openListing(entry.id),
          );
        }
        return Dismissible(
          key:       ValueKey(entry.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding:   const EdgeInsets.only(right: 20),
            color:     Theme.of(context).colorScheme.error,
            child:     const Icon(
              Icons.delete_outline_rounded,
              color: Colors.white,
            ),
          ),
          onDismissed: (_) => _deleteListing(entry),
          child: _ListingRow(
            entry: entry,
            counts: _counts[entry.id],
            onTap: () => _openListing(entry.id),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Listing row
// ---------------------------------------------------------------------------

class _ListingRow extends StatelessWidget {
  final CardList entry;

  /// Null while counts are still loading, or for a list with no entries.
  final ({int copies, int unique})? counts;

  final VoidCallback onTap;

  const _ListingRow({
    required this.entry,
    required this.counts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final copies  = counts?.copies ?? 0;
    final unique  = counts?.unique ?? 0;
    // Copies and unique rows differ as soon as a card is held in multiples, and
    // the difference is the interesting part — showing one number hides it.
    final subtitle = [
      '$copies ${copies == 1 ? 'card' : 'cards'}',
      if (unique != copies) '$unique unique',
      _formatDate(
        DateTime.fromMillisecondsSinceEpoch(entry.createdAt * 1000),
      ),
    ].join(' · ');

    return ListTile(
      onTap:    onTap,
      title:    Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

// ---------------------------------------------------------------------------
// Create listing dialog
// ---------------------------------------------------------------------------

class _CreateListingDialog extends StatefulWidget {
  const _CreateListingDialog();

  @override
  State<_CreateListingDialog> createState() => _CreateListingDialogState();
}

class _CreateListingDialogState extends State<_CreateListingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('New listing'),
      content: TextField(
        controller:           _controller,
        autofocus:            true,
        textCapitalization:   TextCapitalization.sentences,
        textInputAction:      TextInputAction.done,
        onSubmitted:          (_) => _submit(),
        onChanged:            (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText:       'Listing name',
          border:         OutlineInputBorder(),
          isDense:        true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:     const Text('Cancel'),
        ),
        FilledButton(
          onPressed: hasText ? _submit : null,
          child:     const Text('Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Camera permission warning banner
// ---------------------------------------------------------------------------

class _CameraWarningBanner extends StatelessWidget {
  final PermissionStatus _status;
  final VoidCallback     onOpenSettings;

  const _CameraWarningBanner({
    required PermissionStatus status,
    required this.onOpenSettings,
  }) : _status = status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color:   cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.camera_alt_outlined, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Camera ${_status.name}. Scanning will be unavailable.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
          if (_status.isPermanentlyDenied) ...[
            const SizedBox(width: 8),
            TextButton(
              style:     TextButton.styleFrom(
                foregroundColor: cs.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: onOpenSettings,
              child:     const Text('Settings'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Short date format without the `intl` package — e.g. "1 Jun 2026".
String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

// ---------------------------------------------------------------------------
// Card data row
// ---------------------------------------------------------------------------

/// The pinned footer into the card data screen.
///
/// Also where an available update announces itself, in **words** rather than a
/// dot — the size is the number that decides whether now is the moment, and a
/// dot can only say "something".
class _CardDataRow extends StatelessWidget {
  /// Matches a `ListTile`'s dense height closely enough to lift the FAB by.
  static const double height = 60;

  final int? cardCount;
  final String updatedAt;
  final bool updateAvailable;
  final bool updating;
  final VoidCallback onTap;

  const _CardDataRow({
    required this.cardCount,
    required this.updatedAt,
    required this.updateAvailable,
    required this.updating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);

    return Material(
      color: t.surface2,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          top: false,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: updateAvailable && !updating ? t.warning : t.textDim,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Card data',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(),
                        style: PickerTokens.mono(context, size: 11).copyWith(
                          color: updateAvailable && !updating
                              ? t.warning
                              : t.textFaint,
                          fontWeight: updateAvailable && !updating
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: t.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    // The badge is words, not a dot. The size is the number that decides
    // whether now is the moment, and a dot can only say "something".
    if (updating) return 'Updating…';
    if (updateAvailable) {
      return 'Update available — ${CardDataUpdater.downloadSize}';
    }

    final n = cardCount;
    if (n == null) return 'Counting…';
    final parts = ['${_thousands(n)} cards'];
    final d = DateTime.tryParse(updatedAt);
    if (d != null) parts.add('${d.day} ${_shortMonths[d.month - 1]}');
    return parts.join(' · ');
  }

  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _thousands(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

/// `endFloat`, raised by [lift] so the FAB clears a pinned footer.
class _EndFloatAbove extends StandardFabLocation
    with FabEndOffsetX, FabFloatOffsetY {
  final double lift;
  const _EndFloatAbove(this.lift);

  @override
  double getOffsetY(ScaffoldPrelayoutGeometry geometry, double adjustment) =>
      super.getOffsetY(geometry, adjustment) - lift;

  @override
  String toString() => 'FloatingActionButtonLocation.endFloat(above: $lift)';
}
