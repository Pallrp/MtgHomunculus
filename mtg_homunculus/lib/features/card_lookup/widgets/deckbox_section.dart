import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sync.dart';
import '../external/external_dao.dart';
import '../theme/picker_tokens.dart';
import 'deckbox_login_dialog.dart';
import 'deckbox_rows.dart' show DeckboxTints;

/// The lists folder's **Deckbox** part: one foldable group per account, its
/// lists inside. From the Deckbox Integration UI canvas, *Lists folder* and
/// *Account group states*.
///
/// The group header carries no staged count — it could not say which list
/// holds them; counts sit on the lists.
class DeckboxSection extends StatefulWidget {
  const DeckboxSection({
    super.key,
    required this.accounts,
    required this.lists,
    required this.counts,
    required this.staged,
    required this.onOpenList,
  });

  final List<ExternalAccount> accounts;
  final List<ExternalList> lists;
  final Map<int, ExternalCounts> counts;

  /// Staged changes per list id.
  final Map<int, int> staged;
  final void Function(ExternalList list) onOpenList;

  @override
  State<DeckboxSection> createState() => _DeckboxSectionState();
}

class _DeckboxSectionState extends State<DeckboxSection> {
  /// Whose rows a list's counts come from: a Tradelist stores none — it is its
  /// Inventory's rows (tradelist.md), so it counts those, for trade.
  int _mirrorOf(ExternalList list) {
    if (list.kind != 'tradelist') return list.id;
    return widget.lists
            .where((l) => l.accountId == list.accountId && l.kind == 'inventory')
            .firstOrNull
            ?.id ??
        list.id;
  }

  /// Folded groups. Session-only: every group opens unfolded.
  final _folded = <int>{};

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return ValueListenableBuilder<Set<int>>(
      valueListenable: DeckboxSync.instance.pulling,
      builder: (context, pulling, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text('DECKBOX', style: PickerTokens.fieldLabel(context)),
          ),
          for (final account in widget.accounts) ...[
            _AccountHeader(
              account: account,
              lists: [for (final l in widget.lists) if (l.accountId == account.id) l],
              pulling: pulling,
              folded: _folded.contains(account.id),
              onToggle: () => setState(() => _folded.contains(account.id)
                  ? _folded.remove(account.id)
                  : _folded.add(account.id)),
            ),
            if (!_folded.contains(account.id))
              for (final list in widget.lists)
                if (list.accountId == account.id)
                  _ListRow(
                    list: list,
                    counts: widget.counts[_mirrorOf(list)],
                    staged: widget.staged[list.id] ?? 0,
                    pulling: pulling.contains(list.id),
                    onTap: () => widget.onOpenList(list),
                  ),
            Divider(height: 1, color: t.line),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.account,
    required this.lists,
    required this.pulling,
    required this.folded,
    required this.onToggle,
  });

  final ExternalAccount account;
  final List<ExternalList> lists;
  final Set<int> pulling;
  final bool folded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final busy = lists.where((l) => pulling.contains(l.id)).firstOrNull;
    final failed = lists.where((l) => l.lastPullError != null).firstOrNull;
    final last = lists.map((l) => l.lastPulledAt).whereType<int>().fold<int?>(
          null, (a, b) => a == null || b > a ? b : a);

    final (subtitle, subColor) = !account.sessionValid
        ? ('Signed out', t.textDim)
        : busy != null
            ? ('Pulling ${busy.name}…', t.syncInk)
            : failed != null
                ? ("Couldn't read ${failed.name}", t.warning)
                : (last == null ? 'Not pulled yet' : 'Pulled ${pulledAgo(last)}', t.textDim);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: t.surface,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                    color: t.textDim,
                    semanticLabel: folded ? 'Expand ${account.username}' : 'Collapse ${account.username}',
                  ),
                ),
                Opacity(
                  opacity: account.sessionValid ? 1 : 0.55,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.inventory_2_outlined, size: 18, color: t.textDim),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.username,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: account.sessionValid ? t.text : t.textDim,
                        ),
                      ),
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: subColor)),
                    ],
                  ),
                ),
                if (!account.sessionValid)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: OutlinedButton(
                      onPressed: () => logInAgain(context),
                      child: const Text('Log in'),
                    ),
                  ),
                IconButton(
                  tooltip: 'Account actions for ${account.username}',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: () => showAccountSheet(context, account),
                ),
              ]),
            ),
          ),
        ),
        if (busy != null) LinearProgressIndicator(minHeight: 3, color: t.sync, backgroundColor: t.syncSoft),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.list,
    required this.counts,
    required this.staged,
    required this.pulling,
    required this.onTap,
  });

  final ExternalList list;
  final ExternalCounts? counts;
  final int staged;
  final bool pulling;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final c = counts;
    final trade = list.kind == 'tradelist';
    final copies = trade ? c?.forTrade ?? 0 : c?.copies ?? 0;
    final unique = trade ? c?.tradeUnique : c?.unique;
    final subtitle = list.lastPulledAt == null
        ? (pulling ? 'Pulling…' : 'Not pulled yet')
        : [
            '$copies ${copies == 1 ? 'copy' : 'copies'}',
            if (unique != null && unique != copies) '$unique unique',
            if (list.stale) 'out of date',
          ].join(' · ');

    return Material(
      // The list's hue — blue, green, yellow — as on its pills.
      color: t.listTint(list.kind),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 60, right: 12),
        onTap: onTap,
        title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          list.lastPullError != null ? "Couldn't read it — tap to see why" : subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: list.lastPullError != null ? t.warning : t.textDim,
          ),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (staged > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: t.syncSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$staged staged',
                style: PickerTokens.mono(context, size: 11, weight: FontWeight.w600, color: t.syncInk),
              ),
            ),
          Icon(Icons.chevron_right_rounded, color: t.textFaint),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account sheet
// ---------------------------------------------------------------------------

/// *Account actions*: each list with its own pull, *Log out*, *Remove from this
/// phone*. No "pull everything" — a pull per list, as decided.
///
/// **Sized to its content and scrollable** (M2 bug #3): a default bottom sheet
/// is capped at ~9/16 of the screen, which cut *Log out* and *Remove* off
/// behind the navigation bar.
Future<void> showAccountSheet(BuildContext context, ExternalAccount account) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AccountSheet(accountId: account.id, host: context),
    );

/// The sheet's content, **watched from the database** (M2 bug #4): it was
/// built from a snapshot of the lists taken when it opened, so a pull run from
/// it finished without its *Pulled …* line changing. Now a finished pull — or
/// a log out — redraws it. No timer: the line changes when a pull changes it.
class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.accountId, required this.host});

  final int accountId;

  /// The screen the sheet was opened from — what the login dialog and the
  /// remove confirmation open on, once the sheet itself has closed.
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final dao = CollectionDatabase.instance.externalDao;

    return SafeArea(
      child: StreamBuilder<List<ExternalAccount>>(
        stream: dao.watchAccounts(),
        builder: (context, accountsSnap) {
          final account = accountsSnap.data?.where((a) => a.id == accountId).firstOrNull;
          if (account == null) return const SizedBox(height: 120);
          return StreamBuilder<List<ExternalList>>(
            stream: dao.watchLists(),
            builder: (context, listsSnap) {
              final lists = [
                for (final l in listsSnap.data ?? const <ExternalList>[])
                  if (l.accountId == accountId) l,
              ];
              return ValueListenableBuilder<Set<int>>(
                valueListenable: DeckboxSync.instance.pulling,
                builder: (context, pulling, _) => SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: Icon(Icons.inventory_2_outlined, color: t.textDim),
                        title: Text(
                          account.username,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          account.sessionValid ? 'Deckbox · signed in' : 'Deckbox · signed out',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('LISTS', style: PickerTokens.fieldLabel(context)),
                      ),
                      for (final l in lists)
                        ListTile(
                          title: Text(l.name),
                          subtitle: Text(
                            l.stale
                                ? 'Out of date'
                                : l.lastPulledAt == null
                                    ? 'Not pulled yet'
                                    : 'Pulled ${pulledAgo(l.lastPulledAt!)}',
                          ),
                          trailing: pulling.contains(l.id)
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : IconButton(
                                  tooltip: 'Pull ${l.name}',
                                  icon: const Icon(Icons.sync_rounded),
                                  onPressed: account.sessionValid
                                      ? () => DeckboxSync.instance.pull(l)
                                      : null,
                                ),
                        ),
                      const Divider(height: 16),
                      if (account.sessionValid)
                        ListTile(
                          leading: const Icon(Icons.logout_rounded),
                          title: const Text('Log out'),
                          subtitle: const Text('Lists and staged changes stay.'),
                          onTap: () async {
                            Navigator.pop(context);
                            await DeckboxSync.instance.logOut(account);
                          },
                        )
                      else
                        ListTile(
                          leading: const Icon(Icons.login_rounded),
                          title: const Text('Log in'),
                          onTap: () {
                            Navigator.pop(context);
                            logInAgain(host);
                          },
                        ),
                      ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: t.vermilion),
                        title: Text('Remove from this phone', style: TextStyle(color: t.vermilion)),
                        subtitle: const Text('Nothing on Deckbox changes.'),
                        onTap: () async {
                          Navigator.pop(context);
                          final ok = await _confirmRemove(host, account);
                          if (ok) await DeckboxSync.instance.removeAccount(account);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<bool> _confirmRemove(BuildContext context, ExternalAccount account) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${account.username}?'),
        content: const Text(
          'Its lists and their copy on this phone are deleted. '
          'Nothing on Deckbox changes, and you can log in again any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PickerTokens.of(ctx).vermilion),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ??
    false;

/// Logging in again — the same dialog as adding an account. Logging in as the
/// same user finds the same account, so its lists and mirror are picked up.
Future<void> logInAgain(BuildContext context) async {
  final login = await DeckboxLoginDialog.show(context);
  if (login == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Signed in as ${login.account.username}'),
    duration: const Duration(seconds: 2),
  ));
}

/// "just now", "4 min ago", "3 h ago", "2 days ago".
String pulledAgo(int unixSeconds) {
  final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 - unixSeconds;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  if (s < 86400) return '${s ~/ 3600} h ago';
  final d = s ~/ 86400;
  return d == 1 ? 'yesterday' : '$d days ago';
}
