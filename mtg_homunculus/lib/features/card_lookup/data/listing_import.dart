import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import 'collection_database.dart';

/// One-shot import of the JSON listings that predate `collection.db`.
///
/// Listings used to live as `card_lookup/{uuid}.json` with an `_index.json`
/// alongside. That store is gone, but a user's lists are the one thing here that
/// cannot be rebuilt from the network, so they are carried across rather than
/// dropped on upgrade.
///
/// **The JSON files are left on disk.** They cost a few kilobytes and they are
/// the only copy of anything this import gets wrong; deleting them would turn a
/// recoverable mistake into a permanent one. A later release can clean them up
/// once the new store has proven itself.
abstract final class ListingImport {
  static const _subdir = 'card_lookup';
  static const _marker = '.imported';

  /// Import any legacy listings, once.
  ///
  /// Returns how many lists were imported — zero on every run after the first,
  /// and on a fresh install that never had the old store.
  static Future<int> run(CollectionDatabase db) async {
    try {
      final dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, _subdir),
      );
      if (!await dir.exists()) return 0;

      // A marker file rather than a `meta` row: the thing being guarded lives on
      // the filesystem, so the flag saying "already handled" belongs beside it
      // and survives the database being rebuilt.
      final marker = File(p.join(dir.path, _marker));
      if (await marker.exists()) return 0;

      final index = File(p.join(dir.path, '_index.json'));
      if (!await index.exists()) {
        await marker.writeAsString(DateTime.now().toIso8601String());
        return 0;
      }

      final ids = <String>[];
      for (final e in jsonDecode(await index.readAsString()) as List) {
        final id = (e as Map<String, dynamic>)['id'];
        if (id is String) ids.add(id);
      }

      var imported = 0;
      for (final id in ids) {
        if (await _importOne(db, dir, id)) imported++;
      }

      await marker.writeAsString(DateTime.now().toIso8601String());
      if (imported > 0) {
        AppLogger.i('ListingImport: carried $imported list(s) into collection.db');
      }
      return imported;
    } catch (e, st) {
      // Never block entry to the sub-app. The JSON is still on disk, so a
      // failure here costs nothing that cannot be retried by deleting the
      // marker.
      AppLogger.w('ListingImport failed', error: e, stackTrace: st);
      return 0;
    }
  }

  static Future<bool> _importOne(
    CollectionDatabase db,
    Directory dir,
    String id,
  ) async {
    final file = File(p.join(dir.path, '$id.json'));
    if (!await file.exists()) return false;

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final name = (json['name'] as String?)?.trim();
    final cards = json['cards'] as List? ?? const [];
    if (name == null || name.isEmpty) return false;

    final list = await db.createList(name);
    for (final raw in cards) {
      final c = raw as Map<String, dynamic>;
      final printing = c['printing'] as Map<String, dynamic>?;
      if (printing == null) continue;

      final cardId = printing['scryfall_id'] as String?;
      if (cardId == null) continue;

      await db.addCard(
        listId: list.id,
        cardId: cardId,
        name: printing['name'] as String? ?? '?',
        setCode: printing['set_code'] as String? ?? '',
        collectorNumber: printing['collector_number'] as String? ?? '',
        // The old store knew only foil or not — language and condition were
        // never asked for, so they take the app-wide defaults.
        finish: (c['is_foil'] as bool? ?? false) ? Finish.foil : Finish.nonfoil,
        quantity: (c['quantity'] as int?) ?? 1,
      );
    }
    return true;
  }
}
