import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../data/bulk_importer.dart';
import '../data/cards_database.dart';

/// First-run card data setup.
///
/// **Blocks**, deliberately: the card lookup sub-app cannot do anything useful
/// without card data, and a working-looking search that returns nothing is worse
/// than an honest wait. Updates never block — the old database stays live until
/// the atomic swap.
///
/// Progress is determinate wherever a real denominator exists. On a mid-range
/// phone this runs well over a minute, and an indeterminate spinner for that long
/// reads as a hang.
class CardDataSetupScreen extends StatefulWidget {
  final CardsDatabase db;

  /// Called once the database is usable. Image hashing continues in the
  /// background after this fires — see [_Step.images].
  final VoidCallback onReady;

  const CardDataSetupScreen({
    super.key,
    required this.db,
    required this.onReady,
  });

  @override
  State<CardDataSetupScreen> createState() => _CardDataSetupScreenState();
}

class _CardDataSetupScreenState extends State<CardDataSetupScreen> {
  ImportProgress? _progress;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _running = true;
      _progress = null;
    });

    try {
      await for (final p in BulkImporter.run(widget.db)) {
        if (!mounted) return;
        setState(() => _progress = p);
        if (p.step == ImportStep.done) {
          widget.onReady();
          return;
        }
      }
    } catch (e, st) {
      AppLogger.w('Card data setup failed', error: e, stackTrace: st);
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Which step each row represents, in the order they run.
  ///
  /// Image hashing is listed because it is part of the story, but it does not
  /// block: the app is usable the moment the name index is built. The index
  /// describes Scryfall as of its last rebuild, so there are almost always a few
  /// hundred newer printings to hash, and those fall through to the OCR path
  /// until they land.
  static const _steps = [
    (ImportStep.downloading, 'Card data'),
    (ImportStep.inserting, 'Building database'),
    (ImportStep.indexing, 'Name index'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _progress?.step ?? ImportStep.checking;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Setting up card data',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Downloading every Magic card so scanning works offline. '
                    'This happens once.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),

                  for (final (step, label) in _steps)
                    _StepRow(
                      label: label,
                      state: _stateOf(step, current),
                      detail: _detailFor(step),
                      fraction:
                          step == current ? _progress?.fraction : null,
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    _ErrorBlock(error: _error!, onRetry: _running ? null : _start),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _StepState _stateOf(ImportStep step, ImportStep current) {
    if (_error != null && step == current) return _StepState.failed;
    if (current == ImportStep.done) return _StepState.done;
    if (step == current) return _StepState.active;
    return step.index < current.index ? _StepState.done : _StepState.pending;
  }

  /// The number under each label. Always a real tally, never an estimate — see
  /// [ImportProgress].
  String? _detailFor(ImportStep step) {
    final p = _progress;
    if (p == null || p.step != step) return null;
    return switch (step) {
      ImportStep.downloading => '${_mb(p.count)} MB',
      ImportStep.inserting => '${_thousands(p.count)} cards',
      _ => null,
    };
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  static String _thousands(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------------------

enum _StepState { pending, active, done, failed }

class _StepRow extends StatelessWidget {
  final String label;
  final _StepState state;
  final String? detail;

  /// Null means indeterminate for this step — used where no denominator exists.
  final double? fraction;

  const _StepRow({
    required this.label,
    required this.state,
    this.detail,
    this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = state == _StepState.pending;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 26, child: _icon(theme)),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: muted ? theme.disabledColor : null,
                    fontWeight:
                        state == _StepState.active ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (detail != null)
                Text(detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
            ],
          ),
          if (state == _StepState.active) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: fraction, minHeight: 5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _icon(ThemeData theme) => switch (state) {
        _StepState.done => Icon(Icons.check_rounded,
            size: 18, color: theme.colorScheme.primary),
        _StepState.active => const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _StepState.failed => Icon(Icons.error_outline_rounded,
            size: 18, color: theme.colorScheme.error),
        _StepState.pending => Icon(Icons.circle_outlined,
            size: 14, color: theme.disabledColor),
      };
}

class _ErrorBlock extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const _ErrorBlock({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Setup could not finish.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 4),
        Text(
          '$error',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        // Safe to retry: the import replaces rows by primary key, so a partial
        // run leaves no duplicates behind.
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
