import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/collection_database.dart';
import '../data/listing_import.dart';
import 'listing_detail_screen.dart';
import 'quick_scan_screen.dart';

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

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _cameraStatus = status);
  }

  Future<void> _load() async {
    // Carries any pre-collection.db JSON listings across. A no-op on every run
    // but the first, and on a fresh install.
    await ListingImport.run(_db);

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
        actions: [
          IconButton(
            icon:      const Icon(Icons.document_scanner_outlined),
            tooltip:   'Quick Scan',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => const QuickScanScreen()),
            ),
          ),
        ],
      ),
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
