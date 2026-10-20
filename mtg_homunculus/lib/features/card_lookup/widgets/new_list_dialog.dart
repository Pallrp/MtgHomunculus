import 'package:flutter/material.dart';

/// *New listing* — a name, returned on *Create*. Used by the lists folder's
/// **+** and by the destination picker's *New list…*.
class NewListDialog extends StatefulWidget {
  const NewListDialog({super.key});

  @override
  State<NewListDialog> createState() => _NewListDialogState();
}

class _NewListDialogState extends State<NewListDialog> {
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
