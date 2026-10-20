import 'package:flutter/material.dart';

import '../data/collection_database.dart';

/// Card Detail's controls — quantity, finish, language, condition — shared
/// with a Deckbox list's staged addition (M3).
///
/// With [allowAny] each offers **Any** — `null` — as well: a generic Deckbox
/// row sets only what it sets (*any condition*). Without it they behave as
/// they always have.

class QuantityRow extends StatelessWidget {
  final int quantity;
  final void Function(int) onChanged;

  /// What the − says at 1: *Remove from list*, *Unstage*.
  final String removeLabel;

  const QuantityRow({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.removeLabel = 'Remove from list',
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Qty', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          IconButton(
            icon: Icon(quantity <= 1
                ? Icons.delete_outline_rounded
                : Icons.remove_rounded),
            onPressed: () => onChanged(quantity - 1),
            tooltip: quantity <= 1 ? removeLabel : 'One fewer',
          ),
          Text('$quantity', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => onChanged(quantity + 1),
            tooltip: 'One more',
          ),
        ],
      );
}

class _Labelled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labelled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
          ],
        ),
      );
}

/// Finish is not a boolean.
///
/// Scryfall documents `finishes` as an array of **foil**, **nonfoil** and
/// **etched** — three values, not two. The control is built from what the
/// printing actually reports, and **a printing with one finish shows no control
/// at all**: offering a choice that does not exist invites an entry describing a
/// card nobody ever made.
///
/// (`glossy` is a promo *type*, not a finish; those cards report `[foil]`.)
class FinishControl extends StatelessWidget {
  final int? value;
  final int? available;
  final bool allowAny;
  final void Function(int?) onChanged;

  const FinishControl({
    super.key,
    required this.value,
    required this.available,
    required this.onChanged,
    this.allowAny = false,
  });

  /// [SegmentedButton] wants a value for every segment; this one is *Any*.
  static const _any = -1;

  @override
  Widget build(BuildContext context) {
    // Unknown means the card cache is gone; fall back to the three so the entry
    // stays editable rather than freezing on whatever it holds.
    final mask = available ?? (Finish.nonfoil | Finish.foil | Finish.etched);
    final options = [
      if (allowAny) _any,
      for (final f in Finish.all)
        if (mask & f != 0) f,
    ];
    if (options.length < 2) return const SizedBox.shrink();
    final current = value ?? _any;

    return _Labelled(
      label: 'Finish',
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final f in options)
            ButtonSegment(value: f, label: Text(f == _any ? 'Any' : Finish.label(f))),
        ],
        selected: {options.contains(current) ? current : options.first},
        onSelectionChanged: (s) => onChanged(s.first == _any ? null : s.first),
      ),
    );
  }
}

class LanguageControl extends StatelessWidget {
  final String? value;
  final void Function(String?) onChanged;
  final bool allowAny;

  /// What may be picked — Deckbox knows eleven of Scryfall's languages.
  final List<String> options;

  const LanguageControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAny = false,
    this.options = languages,
  });

  /// The languages Scryfall prints cards in.
  static const languages = [
    'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'ru', 'zhs', 'zht',
    'he', 'la', 'grc', 'ar', 'sa', 'ph',
  ];

  @override
  Widget build(BuildContext context) {
    final v = value;
    return _Labelled(
      label: 'Language',
      child: DropdownButton<String?>(
        value: v == null ? (allowAny ? null : 'en') : (options.contains(v) ? v : options.first),
        underline: const SizedBox.shrink(),
        items: [
          if (allowAny) const DropdownMenuItem<String?>(value: null, child: Text('Any')),
          for (final l in options)
            DropdownMenuItem<String?>(value: l, child: Text(l.toUpperCase())),
        ],
        onChanged: (v) => v == null && !allowAny ? null : onChanged(v),
      ),
    );
  }
}

class ConditionControl extends StatelessWidget {
  final int? value;
  final void Function(int?) onChanged;
  final bool allowAny;

  const ConditionControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAny = false,
  });

  @override
  Widget build(BuildContext context) => _Labelled(
        label: 'Condition',
        child: DropdownButton<int?>(
          value: value ?? (allowAny ? null : Condition.nearMint),
          underline: const SizedBox.shrink(),
          items: [
            if (allowAny) const DropdownMenuItem<int?>(value: null, child: Text('Any')),
            for (final c in Condition.all)
              DropdownMenuItem<int?>(value: c, child: Text(Condition.label(c))),
          ],
          onChanged: (v) => v == null && !allowAny ? null : onChanged(v),
        ),
      );
}
