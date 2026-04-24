import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app_theme.dart';
import '../models/format_preset.dart';
import '../services/settings_service.dart';

class FormatPresetList extends StatelessWidget {
  final SettingsService service;

  const FormatPresetList({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Format Presets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add format',
            onPressed: () => _showEditDialog(context),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<FormatPreset>>(
        valueListenable: service.formatPresetsNotifier,
        builder: (context, presets, _) {
          if (presets.isEmpty) {
            return const Center(
              child: Text('No formats yet',
                  style: TextStyle(color: Colors.white38)),
            );
          }
          return Column(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: presets.length,
                  onReorder: service.reorderFormatPresets,
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    return Dismissible(
                      key: Key(preset.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red.withValues(alpha: 0.25),
                        child: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                      onDismissed: (_) {
                        service.removeFormatPreset(preset.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${preset.name} removed'),
                            duration: const Duration(seconds: 10),
                            showCloseIcon: true,
                            closeIconColor: Colors.white70,
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () => service.addFormatPreset(preset),
                            ),
                          ),
                        );
                      },
                      child: ListTile(
                        title: Text(preset.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${preset.startingLife} life · ${preset.playerCount} players',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        onTap: () => _showEditDialog(context, existing: preset),
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

  void _showEditDialog(BuildContext context, {FormatPreset? existing}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _FormatEditDialog(
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
class _FormatEditDialog extends StatefulWidget {
  final SettingsService service;
  final FormatPreset? existing;

  const _FormatEditDialog({required this.service, this.existing});

  @override
  State<_FormatEditDialog> createState() => _FormatEditDialogState();
}

class _FormatEditDialogState extends State<_FormatEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _lifeCtrl;
  late final TextEditingController _countCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.existing?.name ?? '');
    _lifeCtrl  = TextEditingController(
        text: widget.existing != null ? '${widget.existing!.startingLife}' : '');
    _countCtrl = TextEditingController(
        text: widget.existing != null ? '${widget.existing!.playerCount}' : '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lifeCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name  = _nameCtrl.text.trim();
    final life  = int.tryParse(_lifeCtrl.text.trim()) ?? 0;
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (name.isEmpty || life <= 0 || count <= 0) return;
    if (widget.existing == null) {
      widget.service.addFormatPreset(FormatPreset(
        id:           DateTime.now().microsecondsSinceEpoch.toString(),
        name:         name,
        startingLife: life,
        playerCount:  count,
      ));
    } else {
      widget.service.updateFormatPreset(
        widget.existing!.copyWith(name: name, startingLife: life, playerCount: count),
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
              isNew ? 'New Format' : 'Edit Format',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'Name'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _field(_lifeCtrl,  'Starting life', numeric: true)),
              const SizedBox(width: 10),
              Expanded(child: _field(_countCtrl, 'Players',       numeric: true)),
            ]),
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

  Widget _field(TextEditingController ctrl, String label,
      {bool numeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}
