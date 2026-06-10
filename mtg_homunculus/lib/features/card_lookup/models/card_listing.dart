import 'package:uuid/uuid.dart';
import 'listing_card.dart';

const _uuid = Uuid();

/// A named collection of [ListingCard]s — the primary unit the user manages.
///
/// Stored as one JSON file per listing in the app documents directory.
/// The [ListingStorage] service keeps a separate index file so the home
/// screen can display summaries without loading every listing.
class CardListing {
  /// Local UUID — also used as the storage filename.
  final String id;

  final String name;

  final DateTime createdAt;

  final List<ListingCard> cards;

  const CardListing({
    required this.id,
    required this.name,
    required this.createdAt,
    this.cards = const [],
  });

  /// Create a new listing with a fresh UUID and the current timestamp.
  factory CardListing.create({required String name}) {
    return CardListing(
      id:        _uuid.v4(),
      name:      name,
      createdAt: DateTime.now(),
    );
  }

  /// Total copy count across all entries (sum of quantities).
  int get cardCount => cards.fold(0, (sum, c) => sum + c.quantity);

  CardListing copyWith({
    String?          name,
    List<ListingCard>? cards,
  }) {
    return CardListing(
      id:        id,
      name:      name  ?? this.name,
      createdAt: createdAt,
      cards:     cards ?? this.cards,
    );
  }

  // ---------------------------------------------------------------------------
  // Local storage serialisation
  // ---------------------------------------------------------------------------

  factory CardListing.fromJson(Map<String, dynamic> json) {
    return CardListing(
      id:        json['id']   as String,
      name:      json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      cards:     (json['cards'] as List<dynamic>)
          .map((e) => ListingCard.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id':         id,
        'name':       name,
        'created_at': createdAt.toIso8601String(),
        'cards':      cards.map((c) => c.toJson()).toList(),
      };
}
