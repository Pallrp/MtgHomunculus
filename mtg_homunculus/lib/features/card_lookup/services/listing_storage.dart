import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/card_listing.dart';
import '../models/listing_index_entry.dart';

/// File-based persistence for [CardListing] data.
///
/// Layout inside the app documents directory:
/// ```
/// card_lookup/
///   _index.json       ← List<ListingIndexEntry> (home screen summaries)
///   {uuid}.json       ← Full CardListing (one file per listing)
/// ```
///
/// All methods are static — the service is stateless; it only reads and
/// writes files on demand.
class ListingStorage {
  ListingStorage._();

  static const _subdir    = 'card_lookup';
  static const _indexName = '_index.json';

  // ---------------------------------------------------------------------------
  // Path helpers
  // ---------------------------------------------------------------------------

  /// Returns (and creates if needed) the card_lookup storage directory.
  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir  = Directory('${docs.path}/$_subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _listingFile(String id) async {
    final d = await _dir();
    return File('${d.path}/$id.json');
  }

  static Future<File> _indexFile() async {
    final d = await _dir();
    return File('${d.path}/$_indexName');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Load index entries for the home screen, sorted newest-first.
  ///
  /// Returns an empty list on first run (before any listing exists).
  static Future<List<ListingIndexEntry>> loadIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];
    final raw = await file.readAsString(encoding: utf8);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ListingIndexEntry.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Load a full [CardListing] by id.  Returns null if the file is missing.
  static Future<CardListing?> loadListing(String id) async {
    final file = await _listingFile(id);
    if (!await file.exists()) return null;
    final raw = await file.readAsString(encoding: utf8);
    return CardListing.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Persist a listing and update its index entry.
  ///
  /// Covers both create (new UUID) and update (existing UUID) — the caller
  /// does not need to distinguish between them.
  static Future<void> saveListing(CardListing listing) async {
    final file = await _listingFile(listing.id);
    await file.writeAsString(
      jsonEncode(listing.toJson()),
      encoding: utf8,
    );
    await _upsertIndex(ListingIndexEntry.fromListing(listing));
  }

  /// Delete a listing file and remove it from the index.
  ///
  /// No-op (does not throw) if the listing does not exist.
  static Future<void> deleteListing(String id) async {
    final file = await _listingFile(id);
    if (await file.exists()) await file.delete();
    await _removeFromIndex(id);
  }

  /// Convenience: create a new listing, persist it, and return it.
  static Future<CardListing> createListing({required String name}) async {
    final listing = CardListing.create(name: name);
    await saveListing(listing);
    return listing;
  }

  // ---------------------------------------------------------------------------
  // Index helpers
  // ---------------------------------------------------------------------------

  static Future<void> _upsertIndex(ListingIndexEntry entry) async {
    final entries = await loadIndex();
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i == -1) {
      entries.add(entry);
    } else {
      entries[i] = entry;
    }
    await _writeIndex(entries);
  }

  static Future<void> _removeFromIndex(String id) async {
    final entries = await loadIndex()
      ..removeWhere((e) => e.id == id);
    await _writeIndex(entries);
  }

  static Future<void> _writeIndex(List<ListingIndexEntry> entries) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
      encoding: utf8,
    );
  }
}
