import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';

void showCoinFlipDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _CoinFlipDialog(),
  );
}

class _CoinFlipDialog extends StatefulWidget {
  const _CoinFlipDialog();

  @override
  State<_CoinFlipDialog> createState() => _CoinFlipDialogState();
}

class _CoinFlipDialogState extends State<_CoinFlipDialog> {
  bool? _result;
  int _flipCount = 0;
  final List<bool> _history = [];

  void _flip() {
    final result = Random().nextBool();
    setState(() {
      _result = result;
      _flipCount++;
      _history.insert(0, result);
      if (_history.length > 5) _history.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.dialogBg,
      shape: AppTheme.dialogShape,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Coin Flip',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 72,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
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
                        _result! ? 'HEADS' : 'TAILS',
                        key: ValueKey(_flipCount),
                        style: TextStyle(
                          color: _result! ? Colors.amber : Colors.blueGrey.shade300,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _flip,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Flip',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _history
                    .map((r) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: r
                                ? Colors.amber.withValues(alpha: 0.15)
                                : Colors.blueGrey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            r ? 'H' : 'T',
                            style: TextStyle(
                              color: r ? Colors.amber : Colors.blueGrey.shade300,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
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
