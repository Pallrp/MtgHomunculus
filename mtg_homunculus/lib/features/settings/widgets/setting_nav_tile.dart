import 'package:flutter/material.dart';

/// A tappable list tile with a trailing arrow — opens a sub-page.
class SettingNavTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onTap;
  final bool enabled;

  const SettingNavTile({
    super.key,
    required this.label,
    this.subtitle,
    this.leading,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: leading,
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
