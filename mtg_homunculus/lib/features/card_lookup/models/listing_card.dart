import 'package:uuid/uuid.dart';
import 'scryfall_card.dart';

const _uuid = Uuid();

/// One distinct card entry in a [CardListing].
///
/// Identified by a local UUID ([id]).  Two cards with the same Scryfall
/// printing *and* the same [isFoil] flag are considered duplicates by the
/// scan pipeline — their [quantity] is incremented rather than adding a new
/// row.
class ListingCard {
  /// Local UUID — stable across saves.
  final String id;

  /// The chosen Scryfall printing.
  final ScryfallCard printing;

  /// Whether this entry represents a foil copy.  Defaults to false.
  final bool isFoil;

  /// How many copies.  Incremented when a duplicate scan is detected.
  /// Always ≥ 1.
  final int quantity;

  const ListingCard({
    required this.id,
    required this.printing,
    this.isFoil = false,
    this.quantity = 1,
  });

  /// Create a new card entry with a fresh UUID.
  factory ListingCard.create({
    required ScryfallCard printing,
    bool isFoil = false,
  }) {
    return ListingCard(
      id:       _uuid.v4(),
      printing: printing,
      isFoil:   isFoil,
    );
  }

  ListingCard copyWith({
    ScryfallCard? printing,
    bool?         isFoil,
    int?          quantity,
  }) {
    return ListingCard(
      id:       id,
      printing: printing ?? this.printing,
      isFoil:   isFoil   ?? this.isFoil,
      quantity: quantity  ?? this.quantity,
    );
  }

  // ---------------------------------------------------------------------------
  // Local storage serialisation
  // ---------------------------------------------------------------------------

  factory ListingCard.fromJson(Map<String, dynamic> json) {
    return ListingCard(
      id:       json['id']       as String,
      printing: ScryfallCard.fromJson(json['printing'] as Map<String, dynamic>),
      isFoil:   json['is_foil']  as bool,
      quantity: json['quantity'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':       id,
        'printing': printing.toJson(),
        'is_foil':  isFoil,
        'quantity': quantity,
      };
}
