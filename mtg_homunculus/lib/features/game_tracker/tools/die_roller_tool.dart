import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';

void showDieRollerDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _DieRollerDialog(),
  );
}

const _kDice = [4, 6, 8, 10, 12, 20];

class _DieRollerDialog extends StatefulWidget {
  const _DieRollerDialog();

  @override
  State<_DieRollerDialog> createState() => _DieRollerDialogState();
}

class _DieRollerDialogState extends State<_DieRollerDialog> {
  int? _result;
  int? _lastDie;
  int _rollCount = 0;
  final List<(int die, int result)> _history = [];

  void _roll(int faces) {
    final result = Random().nextInt(faces) + 1;
    setState(() {
      _result = result;
      _lastDie = faces;
      _rollCount++;
      _history.insert(0, (faces, result));
      if (_history.length > 5) _history.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.dialogBg,
      shape: AppTheme.dialogShape,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Die Roller',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _kDice
                  .map((d) => GestureDetector(
                        onTap: () => _roll(d),
                        child: Container(
                          width: 52,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _lastDie == d
                                ? Colors.blueGrey.shade700
                                : Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'd$d',
                            style: TextStyle(
                              color: _lastDie == d ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 72,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: _result == null
                    ? const Text(
                        '?',
                        key: ValueKey('none'),
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Text(
                        '$_result',
                        key: ValueKey(_rollCount),
                        style: TextStyle(
                          // Highlight maximum roll (nat max on any die) in gold.
                          color: _result == _lastDie ? Colors.amber : Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: _history
                    .map((h) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'd${h.$1}: ${h.$2}',
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
