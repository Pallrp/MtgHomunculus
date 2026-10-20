import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sheet_model.dart' show ScanTarget;
import '../theme/picker_tokens.dart';
import 'deckbox_rows.dart' show DeckboxTints;
import 'new_list_dialog.dart';

/// Where *Cut to* or *Copy to* sends cards.
sealed class Destination {
  const Destination();
}

/// The other staged section of the Deckbox list the cards are in.
final class ToSection extends Destination {
  const ToSection(this.section);
  final ScanTarget section;
}

final class ToAppList extends Destination {
  const ToAppList(this.list);
  final CardList list;
}

final class ToDeckbox extends Destination {
  const ToDeckbox(this.list, this.account);
  final ExternalList list;
  final ExternalAccount account;
}

/// The destination picker — what the trailing preposition in *Cut to* and
/// *Copy to* promises (M3 step 4, the canvas's *Copy to: destination*):
///
/// ```
/// This list      To add / To remove      a Deckbox list's other section; Cut only
/// New list…                              an app list, named on the spot
/// Unsorted, …                            the app lists
/// Deckbox · palli                        each account's lists
/// ```
///
/// No staged counts: a destination is chosen by name.
Future<Destination?> pickDestination(
  BuildContext context, {
  required String title,
  List<ScanTarget> thisList = const [],
  int? excludeAppList,
  int? excludeDeckboxList,
}) async {
  final db = CollectionDatabase.instance;
  final appLists = [for (final l in await db.allLists()) if (l.id != excludeAppList) l];
  final accounts = await db.externalDao.watchAccounts().first;
  final deckbox = [
    for (final a in accounts)
      (account: a, lists: [for (final l in await db.externalDao.listsFor(a.id)) if (l.id != excludeDeckboxList) l]),
  ];
  if (!context.mounted) return null;

  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final t = PickerTokens.of(sheetContext);
      Widget head(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(text.toUpperCase(), style: PickerTokens.fieldLabel(sheetContext)),
          );
      Widget item(String label, Object value, {bool accent = false, String? kind}) => ListTile(
            // A Deckbox list wears its hue, as in the lists folder.
            tileColor: kind == null ? null : t.listTint(kind),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
                color: accent ? t.accent : t.text,
              ),
            ),
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86),
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text)),
          ),
          if (thisList.isNotEmpty) ...[
            head('This list'),
            for (final s in thisList) item(s.label, ToSection(s), accent: true),
            const Divider(height: 16, thickness: 8),
          ],
          item('New list…', const _NewList(), accent: true),
          for (final l in appLists) item(l.name, ToAppList(l)),
          for (final d in deckbox)
            if (d.lists.isNotEmpty) ...[
              head('Deckbox · ${d.account.username}'),
              for (final l in d.lists) item(l.name, ToDeckbox(l, d.account), kind: l.kind),
            ],
          const SizedBox(height: 12),
        ]),
      );
    },
  );

  if (picked is _NewList) {
    if (!context.mounted) return null;
    final name = await showDialog<String>(context: context, builder: (_) => const NewListDialog());
    if (name == null || name.isEmpty) return null;
    return ToAppList(await db.createList(name));
  }
  return picked as Destination?;
}

final class _NewList {
  const _NewList();
}

/// *Stage N cards in Inventory* — **Add** or **Remove**, the question a
/// Deckbox list as a destination asks. True for Add.
Future<bool?> pickDirection(
  BuildContext context, {
  required int cards,
  required ExternalList list,
  required ExternalAccount account,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final t = PickerTokens.of(sheetContext);
        Widget option(String label, IconData icon, Color color, bool value) => Expanded(
              child: InkWell(
                onTap: () => Navigator.of(sheetContext).pop(value),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    CircleAvatar(radius: 20, backgroundColor: color, child: Icon(icon, color: Colors.white)),
                    const SizedBox(height: 10),
                    Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
                  ]),
                ),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Stage $cards ${cards == 1 ? 'card' : 'cards'} in ${list.name}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text),
              ),
              Text(account.username, style: PickerTokens.mono(sheetContext, size: 11.5)),
              const SizedBox(height: 16),
              Row(children: [
                option('Add', Icons.add_rounded, t.sync, true),
                const SizedBox(width: 10),
                option('Remove', Icons.remove_rounded, t.text, false),
              ]),
            ]),
          ),
        );
      },
    );
