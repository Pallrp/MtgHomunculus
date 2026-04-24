import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../../game_tracker/models/tracker.dart';
import '../services/settings_service.dart';

class PresetTrackerList extends StatelessWidget {
  final SettingsService service;

  const PresetTrackerList({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracker Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add tracker',
            onPressed: () => _showEditDialog(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Tracker>>(
        valueListenable: service.trackerLibraryNotifier,
        builder: (context, trackers, _) {
          if (trackers.isEmpty) {
            return const Center(
              child: Text('No trackers yet',
                  style: TextStyle(color: Colors.white38)),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: trackers.length,
                  onReorder: service.reorderTrackers,
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
                      onDismissed: (_) {
                        service.removeTracker(tracker.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${tracker.name} removed'),
                            duration: const Duration(seconds: 10),
                            showCloseIcon: true,
                            closeIconColor: Colors.white70,
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => service.addTracker(tracker),
                            ),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: Text(tracker.icon,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(tracker.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          tracker.permanent ? 'Permanent' : 'Resets on pass',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        onTap: () => _showEditDialog(context, existing: tracker),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Swipe left to remove',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, {Tracker? existing}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _TrackerEditDialog(
        service:  service,
        existing: existing,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit / create dialog — owns its own controllers so they are disposed safely
// by the dialog's own State.dispose(), not by the caller after pop.
// ---------------------------------------------------------------------------
class _TrackerEditDialog extends StatefulWidget {
  final SettingsService service;
  final Tracker? existing;

  const _TrackerEditDialog({required this.service, this.existing});

  @override
  State<_TrackerEditDialog> createState() => _TrackerEditDialogState();
}

class _TrackerEditDialogState extends State<_TrackerEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconCtrl;
  late bool _permanent;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.existing?.name ?? '');
    _iconCtrl  = TextEditingController(text: widget.existing?.icon ?? '');
    _permanent = widget.existing?.permanent ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final icon = _iconCtrl.text.trim();
    if (name.isEmpty || icon.isEmpty) return;
    if (widget.existing == null) {
      widget.service.addTracker(Tracker(
        id:        DateTime.now().microsecondsSinceEpoch.toString(),
        icon:      icon,
        name:      name,
        permanent: _permanent,
      ));
    } else {
      widget.service.updateTracker(
        widget.existing!.copyWith(name: name, icon: icon, permanent: _permanent),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Dialog(
      backgroundColor: AppTheme.dialogBg,
      shape: AppTheme.dialogShape,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNew ? 'New Tracker' : 'Edit Tracker',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: TextField(
                    controller: _iconCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: '😀',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2)),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Tracker name',
                      hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.07),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Permanent',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7))),
                const Spacer(),
                Switch(
                  value: _permanent,
                  onChanged: (v) => setState(() => _permanent = v),
                  activeThumbColor: Colors.blueGrey,
                ),
              ],
            ),
            Text(
              _permanent
                  ? 'Keeps value between turns'
                  : 'Resets to 0 on pass',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  child: Text(isNew ? 'Create' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
