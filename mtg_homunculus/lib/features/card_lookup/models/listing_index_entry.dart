import 'card_listing.dart';

/// Lightweight summary of a [CardListing] stored in the index file.
///
/// The index file (`listings_index.json`) holds one [ListingIndexEntry] per
/// listing so [ListingHomeScreen] can render the list without loading every
/// individual listing JSON file.
///
/// [cardCount] is denormalised and updated by [ListingStorage] on every save.
class ListingIndexEntry {
  final String id;
  final String name;
  final DateTime createdAt;

  /// Total copy count (sum of quantities) — kept in sync by the storage layer.
  final int cardCount;

  const ListingIndexEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.cardCount,
  });

  /// Build an index entry from a fully-loaded [CardListing].
  factory ListingIndexEntry.fromListing(CardListing listing) {
    return ListingIndexEntry(
      id:        listing.id,
      name:      listing.name,
      createdAt: listing.createdAt,
      cardCount: listing.cardCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Local storage serialisation
  // ---------------------------------------------------------------------------

  factory ListingIndexEntry.fromJson(Map<String, dynamic> json) {
    return ListingIndexEntry(
      id:        json['id']         as String,
      name:      json['name']       as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      cardCount: json['card_count'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'name':       name,
        'created_at': createdAt.toIso8601String(),
        'card_count': cardCount,
      };
}
