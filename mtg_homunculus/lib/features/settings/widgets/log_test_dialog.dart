import 'package:flutter/material.dart';

import '../../../../core/logging/app_logger.dart';
import '../models/setting_enums.dart';

// [dev-tool] Remove by deleting this file and the trigger tile in settings_screen.dart.
class LogTestDialog extends StatelessWidget {
  final LogLevel currentLevel;

  const LogTestDialog({super.key, required this.currentLevel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log Test'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Active level: ${currentLevel.name}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _LevelButton(
            label: 'Fire Error',
            onTap: () {
              AppLogger.e('Test error entry fired from Log Test dialog');
              _confirm(context, 'Error');
            },
          ),
          const SizedBox(height: 8),
          _LevelButton(
            label: 'Fire Warning',
            onTap: () {
              AppLogger.w('Test warning entry fired from Log Test dialog');
              _confirm(context, 'Warning');
            },
          ),
          const SizedBox(height: 8),
          _LevelButton(
            label: 'Fire Info',
            onTap: () {
              AppLogger.i('Test info entry fired from Log Test dialog');
              _confirm(context, 'Info');
            },
          ),
          const SizedBox(height: 8),
          _LevelButton(
            label: 'Fire Debug',
            onTap: () {
              AppLogger.d('Test debug entry fired from Log Test dialog');
              _confirm(context, 'Debug');
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _confirm(BuildContext context, String level) {
    final willAppear = switch (currentLevel) {
      LogLevel.off     => false,
      LogLevel.errors  => level == 'Error',
      LogLevel.verbose => true,
    };
    final note = willAppear ? 'will appear in log' : 'filtered by current level';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('[$level] entry fired — $note'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _LevelButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LevelButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(label),
    );
  }
}
