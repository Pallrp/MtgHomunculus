import 'package:flutter/material.dart';

import '../theme/picker_tokens.dart';
import 'deckbox_rows.dart';

/// The shape of a "settle these before moving on" screen (M3 step 4): a
/// title and subtitle, a band counting what is still waiting, one row per
/// card, an optional banner below, and **Back** beside a primary action that
/// stays disabled until nothing waits.
///
/// Shared by *Remove from Inventory* (matching to Deckbox rows) and *N cards
/// need a specific printing* (generic cards into an app list).
class ChecklistScaffold extends StatelessWidget {
  const ChecklistScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bandLabel,
    required this.waiting,
    required this.rows,
    required this.primaryLabel,
    required this.onPrimary,
    this.below = const [],
  });

  final String title;
  final String subtitle;

  /// *CHOOSE A COPY*, shown while anything waits.
  final String bandLabel;
  final int waiting;
  final List<Widget> rows;

  /// Under the rows — the skipped-cards banner.
  final List<Widget> below;
  final String primaryLabel;

  /// Null disables it.
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          Text(subtitle, style: PickerTokens.mono(context, size: 11)),
        ]),
      ),
      body: ListView(children: [
        if (waiting > 0)
          Container(
            color: t.ground,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(children: [
              Expanded(child: Text(bandLabel.toUpperCase(), style: PickerTokens.fieldLabel(context))),
              Text('$waiting left', style: PickerTokens.mono(context, size: 11)),
            ]),
          ),
        ...rows,
        ...below,
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back'))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: t.sync),
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One card in a [ChecklistScaffold]: its art, its name, a line under it,
/// and its actions. [dimmed] for a card that was skipped.
class ChecklistRow extends StatelessWidget {
  const ChecklistRow({
    super.key,
    required this.cardRef,
    required this.any,
    required this.title,
    required this.sub,
    required this.trailing,
    this.dimmed = false,
  });

  final String? cardRef;
  final bool any;
  final String title;
  final Widget sub;
  final Widget trailing;
  final bool dimmed;

  /// The green check of a settled card.
  static Widget done(BuildContext context) => CircleAvatar(
        radius: 12,
        backgroundColor: PickerTokens.of(context).accent,
        child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: SizedBox(width: 36, height: 50, child: DeckboxThumb(cardRef: cardRef, any: any)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: dimmed ? t.textDim : t.text),
            ),
            const SizedBox(height: 3),
            sub,
          ]),
        ),
        trailing,
      ]),
    );
  }
}

/// *N skipped: they stay in Trade binder* — and, opened, which.
class SkippedBanner extends StatefulWidget {
  const SkippedBanner({super.key, required this.lines, required this.sourceName});

  final List<String> lines;
  final String sourceName;

  @override
  State<SkippedBanner> createState() => _SkippedBannerState();
}

class _SkippedBannerState extends State<SkippedBanner> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 14),
      color: t.warningBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${widget.lines.length} skipped', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ': they stay in ${widget.sourceName}'),
                ]),
                style: TextStyle(fontSize: 13, color: t.text),
              ),
            ),
            TextButton(onPressed: () => setState(() => _open = !_open), child: Text(_open ? 'Hide' : 'Show')),
          ]),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final s in widget.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(s, style: TextStyle(fontSize: 12.5, color: t.text)),
                ),
            ]),
          ),
      ]),
    );
  }
}
