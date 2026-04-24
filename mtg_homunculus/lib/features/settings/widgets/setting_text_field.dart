import 'package:flutter/material.dart';

/// A labelled text/numeric input for use in sub-page edit forms.
///
/// Uses [TextFormField] so it integrates with [Form] + [FormState.validate].
/// For numeric inputs pass [TextInputType.number] as [keyboardType].
class SettingTextField extends StatefulWidget {
  final String label;
  final String value;
  final TextInputType keyboardType;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String> onChanged;

  const SettingTextField({
    super.key,
    required this.label,
    required this.value,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.validator,
    required this.onChanged,
  });

  @override
  State<SettingTextField> createState() => _SettingTextFieldState();
}

class _SettingTextFieldState extends State<SettingTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(SettingTextField old) {
    super.didUpdateWidget(old);
    // Sync controller if the value was changed externally (e.g. a reset).
    if (old.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      validator: widget.validator,
      onChanged: widget.onChanged,
    );
  }
}
