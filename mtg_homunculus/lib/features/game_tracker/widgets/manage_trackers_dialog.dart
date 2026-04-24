import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../models/tracker.dart';

enum _Mode { manage, pick, create }

class ManageTrackersDialog extends StatefulWidget {
  final List<Tracker> trackers;
  final List<Tracker> trackerLibrary;
  final int quarterTurns;
  final void Function(Tracker tracker) onAdd;
  final void Function(String trackerId) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  const ManageTrackersDialog({
    super.key,
    required this.trackers,
    required this.trackerLibrary,
    required this.quarterTurns,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  State<ManageTrackersDialog> createState() => _ManageTrackersDialogState();
}

class _ManageTrackersDialogState extends State<ManageTrackersDialog> {
  late List<Tracker> _trackers;
  _Mode _mode = _Mode.manage;

  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _iconController = TextEditingController();
  bool _newPermanent = false;

  @override
  void initState() {
    super.initState();
    _trackers = List.from(widget.trackers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  // Library trackers not already on the card, filtered by search query.
  // Takes the library read from GtSettingsScope in build().
  List<Tracker> _availableTrackers(List<Tracker> library) {
    final activeIds = _trackers.map((t) => t.id).toSet();
    final query = _searchController.text.toLowerCase().trim();
    return library
        .where((t) => !activeIds.contains(t.id))
        .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
        .toList();
  }

  void _addTracker(Tracker tracker) {
    setState(() {
      _trackers.add(tracker);
      _mode = _Mode.manage;
    });
    widget.onAdd(tracker);
  }

  void _removeTracker(String trackerId) {
    setState(() => _trackers.removeWhere((t) => t.id == trackerId));
    widget.onRemove(trackerId);
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Flutter passes newIndex as if the item hasn't been removed yet —
    // subtract 1 when moving downward to get the real insertion index.
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _trackers.removeAt(oldIndex);
      _trackers.insert(newIndex, item);
    });
    widget.onReorder(oldIndex, newIndex);
  }

  void _submitCreate() {
    final name = _nameController.text.trim();
    final icon = _iconController.text.trim();
    if (name.isEmpty || icon.isEmpty) return;
    final tracker = Tracker(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      icon: icon,
      name: name,
      permanent: _newPermanent,
    );
    _nameController.clear();
    _iconController.clear();
    setState(() => _newPermanent = false);
    _addTracker(tracker);
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.trackerLibrary;

    // Only rotate in manage mode. Pick/create views contain text fields — the
    // system keyboard always comes from the physical bottom of the screen, so
    // keeping those views portrait lets the keyboard align correctly.
    final angle = _mode == _Mode.manage ? widget.quarterTurns * pi / 2 : 0.0;
    return Transform.rotate(
      angle: angle,
      child: Dialog(
        backgroundColor: AppTheme.dialogBg,
        shape: AppTheme.dialogShape,
        child: SizedBox(
          width: 320,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: switch (_mode) {
                _Mode.manage => _ManageView(
                    key: const ValueKey(_Mode.manage),
                    trackers: _trackers,
                    onReorder: _onReorder,
                    onRemove: _removeTracker,
                    onAddTap: () => setState(() {
                      _searchController.clear();
                      _mode = _Mode.pick;
                    }),
                    onClose: () => Navigator.pop(context),
                  ),
                _Mode.pick => _PickView(
                    key: const ValueKey(_Mode.pick),
                    searchController: _searchController,
                    availableTrackers: _availableTrackers(library),
                    onBack: () => setState(() => _mode = _Mode.manage),
                    onSelect: _addTracker,
                    onCreateTap: () => setState(() => _mode = _Mode.create),
                    onSearchChanged: () => setState(() {}),
                  ),
                _Mode.create => _CreateView(
                    key: const ValueKey(_Mode.create),
                    nameController: _nameController,
                    iconController: _iconController,
                    permanent: _newPermanent,
                    onPermanentChanged: (val) => setState(() => _newPermanent = val),
                    onBack: () => setState(() => _mode = _Mode.pick),
                    onSubmit: _submitCreate,
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Manage view ─────────────────────────────────────────────────────────────

class _ManageView extends StatelessWidget {
  final List<Tracker> trackers;
  final void Function(int, int) onReorder;
  final void Function(String) onRemove;
  final VoidCallback onAddTap;
  final VoidCallback onClose;

  const _ManageView({
    super.key,
    required this.trackers,
    required this.onReorder,
    required this.onRemove,
    required this.onAddTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Trackers',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.5), size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tracker list
          if (trackers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text('No trackers yet',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: trackers.length,
                onReorder: onReorder,
                itemBuilder: (context, index) {
                  final tracker = trackers[index];
                  return Dismissible(
                    key: Key(tracker.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red.withValues(alpha: 0.25),
                      child: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    onDismissed: (_) => onRemove(tracker.id),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      leading: Text(tracker.icon, style: const TextStyle(fontSize: 20)),
                      title: Text(tracker.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        tracker.permanent ? 'Permanent' : 'Resets on pass',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle,
                            color: Colors.white.withValues(alpha: 0.35)),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          // Add button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: onAddTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Text('Add tracker',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pick view ────────────────────────────────────────────────────────────────

class _PickView extends StatelessWidget {
  final TextEditingController searchController;
  final List<Tracker> availableTrackers;
  final VoidCallback onBack;
  final void Function(Tracker) onSelect;
  final VoidCallback onCreateTap;
  final VoidCallback onSearchChanged;

  const _PickView({
    super.key,
    required this.searchController,
    required this.availableTrackers,
    required this.onBack,
    required this.onSelect,
    required this.onCreateTap,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back,
                        color: Colors.white.withValues(alpha: 0.7), size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Add tracker',
                    style: TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon:
                    Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4), size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (_) => onSearchChanged(),
            ),
          ),
          const SizedBox(height: 4),
          // List: "Create new" pinned at top, then filtered saved trackers
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  title: Text('Create new tracker',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                  onTap: onCreateTap,
                ),
                if (availableTrackers.isNotEmpty)
                  const Divider(color: Color(0xFF3A3A3A), height: 1, indent: 20, endIndent: 20),
                ...availableTrackers.map(
                  (tracker) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Text(tracker.icon, style: const TextStyle(fontSize: 20)),
                    title: Text(tracker.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(
                      tracker.permanent ? 'Permanent' : 'Resets on pass',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                    ),
                    onTap: () => onSelect(tracker),
                  ),
                ),
                if (availableTrackers.isEmpty && searchController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No saved trackers match',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Create view ──────────────────────────────────────────────────────────────

class _CreateView extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController iconController;
  final bool permanent;
  final void Function(bool) onPermanentChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  const _CreateView({
    super.key,
    required this.nameController,
    required this.iconController,
    required this.permanent,
    required this.onPermanentChanged,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onBack,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back,
                        color: Colors.white.withValues(alpha: 0.7), size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('New tracker',
                    style: TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + name row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 60,
                      child: TextField(
                        controller: iconController,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 22),
                        maxLength: 4,
                        decoration: InputDecoration(
                          hintText: '😀',
                          hintStyle:
                              TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Tracker name',
                          hintStyle:
                              TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Permanent toggle
                Row(
                  children: [
                    Text('Permanent',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7), fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: permanent,
                      onChanged: onPermanentChanged,
                      activeThumbColor: Colors.blueGrey,
                    ),
                  ],
                ),
                Text(
                  permanent ? 'Keeps value between turns' : 'Resets to 0 on pass',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Create button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: onSubmit,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Create',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
