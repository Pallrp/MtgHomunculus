import 'dart:async';

import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sync.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../theme/picker_tokens.dart';
import '../widgets/attribute_chips.dart';
import '../widgets/card_thumb.dart';
import '../widgets/deckbox_section.dart';

/// One Deckbox list, **read-only** (M2): its *On Deckbox* section — the mirror.
///
/// Opening it pulls, unless it was pulled within the cooldown and is not
/// stale; pulling down pulls regardless. A failed pull keeps the previous
/// mirror and says why. Staging, the scan target and pushing arrive with M3,
/// when this list moves into the listing sheet with the camera.
class DeckboxListScreen extends StatefulWidget {
  const DeckboxListScreen({super.key, required this.listId});

  final int listId;

  @override
  State<DeckboxListScreen> createState() => _DeckboxListScreenState();
}

class _DeckboxListScreenState extends State<DeckboxListScreen> {
  final _dao = CollectionDatabase.instance.externalDao;
  StreamSubscription<ExternalList?>? _listSub;
  StreamSubscription<List<ExternalEntry>>? _entriesSub;
  StreamSubscription<List<ExternalAccount>>? _accountsSub;

  ExternalList? _list;
  List<ExternalAccount> _accounts = const [];
  List<ExternalEntry> _entries = const [];
  bool _openPullDone = false;

  @override
  void initState() {
    super.initState();
    _listSub = _dao.watchList(widget.listId).listen((l) {
      setState(() => _list = l);
      if (l != null && !_openPullDone) {
        _openPullDone = true;
        DeckboxSync.instance.pullIfDue(l);
      }
    });
    _entriesSub = _dao.watchEntries(widget.listId).listen((e) => setState(() => _entries = e));
    _accountsSub = _dao.watchAccounts().listen((all) => setState(() => _accounts = all));
  }

  @override
  void dispose() {
    _listSub?.cancel();
    _entriesSub?.cancel();
    _accountsSub?.cancel();
    super.dispose();
  }

  Future<void> _pull() async {
    final l = _list;
    if (l != null) await DeckboxSync.instance.pull(l);
  }

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final list = _list;
    final account = _accounts.where((a) => a.id == list?.accountId).firstOrNull;
    final isTrade = list?.kind == 'tradelist';

    return Scaffold(
      backgroundColor: t.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(list?.name ?? ''),
            if (list != null)
              Text(
                [
                  ?account?.username,
                  list.lastPulledAt == null ? 'not pulled yet' : 'pulled ${pulledAgo(list.lastPulledAt!)}',
                ].join(' · '),
                style: PickerTokens.mono(context, size: 11),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pull now',
            icon: const Icon(Icons.sync_rounded),
            onPressed: account?.sessionValid == false ? null : _pull,
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: DeckboxSync.instance.pulling,
          builder: (context, pulling, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pulling.contains(widget.listId))
                LinearProgressIndicator(minHeight: 3, color: t.sync, backgroundColor: t.syncSoft),
              if (account != null && !account.sessionValid)
                _Banner(
                  icon: Icons.lock_outline_rounded,
                  text: 'Signed out. The list below is the last copy pulled.',
                  action: 'Log in',
                  onAction: () => logInAgain(context),
                )
              else if (list?.lastPullError case final error?)
                _Banner(
                  icon: Icons.warning_amber_rounded,
                  text: "Couldn't read this list — $error. Nothing changed.",
                  action: 'Retry',
                  onAction: _pull,
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _pull,
                  // Built lazily: an Inventory can hold thousands of rows.
                  child: Builder(builder: (context) {
                    final rows = isTrade
                        ? [for (final e in _entries) if (e.tradeCount > 0) e]
                        : _entries;
                    return ListView.builder(
                      // Always scrollable, so pull-to-refresh works on a short
                      // or empty list too.
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: 1 + (rows.isEmpty ? 1 : rows.length),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _SectionHeader(
                            label: 'On Deckbox',
                            count: rows.fold<int>(0, (n, e) => n + (isTrade ? e.tradeCount : e.count)),
                          );
                        }
                        if (rows.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              list?.lastPulledAt == null ? 'Not pulled yet.' : 'Nothing on this list.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: t.textDim),
                            ),
                          );
                        }
                        return _MirrorRow(entry: rows[i - 1], tradelist: isTrade);
                      },
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label.toUpperCase(), style: PickerTokens.fieldLabel(context)),
        ),
        Text('$count', style: PickerTokens.mono(context, size: 12.5)),
      ]),
    );
  }
}

/// One mirrored row: the card, what Deckbox says about it, and its count.
///
/// Three kinds, told apart on sight: a **mapped** row reads like an app entry;
/// an **any printing** row says so in the set line and carries an *ANY* badge;
/// an **unmapped** row says it could not be matched, and shows Deckbox's own
/// edition so it can still be recognised.
class _MirrorRow extends StatelessWidget {
  const _MirrorRow({required this.entry, required this.tradelist});

  final ExternalEntry entry;
  final bool tradelist;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final e = entry;
    final ref = e.cardRef;
    final unmapped = !e.anyPrinting && e.cardId == null;

    final Widget setLine;
    if (e.anyPrinting) {
      setLine = Text(
        'Any printing',
        style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: t.syncInk),
      );
    } else if (unmapped) {
      setLine = Row(children: [
        Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Not matched · ${e.edition} #${e.cardNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: t.warning),
          ),
        ),
      ]);
    } else {
      setLine = Text(
        '${e.editionCode.toUpperCase()} · ${e.cardNumber} · ${e.edition}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PickerTokens.mono(context, size: 10),
      );
    }

    final extras = [
      if (e.condition == 'Proxy') 'PROXY',
      for (final f in e.rowFlags.split(',')) if (f.isNotEmpty) f.toUpperCase(),
      if (!tradelist && e.tradeCount > 0) '${e.tradeCount} FOR TRADE',
    ];

    return Container(
      constraints: const BoxConstraints(minHeight: PickerTokens.rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        SizedBox(
          width: PickerTokens.thumbWidth,
          height: PickerTokens.thumbHeight,
          child: Stack(children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CardThumb(
                  url: ref == null ? null : ScryfallCard.imageUrlFor(ref, null, size: 'small'),
                ),
              ),
            ),
            if (e.anyPrinting)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: t.sync, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'ANY',
                    style: PickerTokens.mono(context, size: 7, weight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: t.text),
              ),
              setLine,
              const SizedBox(height: 3),
              Wrap(spacing: 3, runSpacing: 3, children: [
                AttributeChips(
                  finish: e.finish,
                  language: e.languageCode,
                  condition: e.conditionCode,
                  defaults: ScanDefaults.current,
                ),
                for (final x in extras)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      border: Border.all(color: t.accent),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(x, style: PickerTokens.mono(context, size: 8.5, color: t.accent)),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          tradelist ? '${e.tradeCount}×' : '${e.count}×',
          style: PickerTokens.mono(context, size: 12.5, weight: FontWeight.w500, color: t.textDim),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Container(
      color: t.warningBg,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(children: [
        Icon(icon, size: 18, color: t.warning),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: t.text))),
        TextButton(onPressed: onAction, child: Text(action)),
      ]),
    );
  }
}
