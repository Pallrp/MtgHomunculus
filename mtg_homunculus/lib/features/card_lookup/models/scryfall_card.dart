/// A single Scryfall card object, as returned by the public Scryfall API.
///
/// Instances are immutable.  Two factories handle the two JSON shapes:
/// - [ScryfallCard.fromScryfallJson] — parses a Scryfall REST API response.
/// - [ScryfallCard.fromJson]         — deserialises from local storage.
class ScryfallCard {
  /// Scryfall's own UUID for this printing.
  final String scryfallId;

  final String name;

  /// Lowercase set code as returned by Scryfall (e.g. "m11", "lea").
  /// Uppercase for display: `setCode.toUpperCase()`.
  final String setCode;

  final String setName;

  /// Collector number string, e.g. "149" or "201a".
  final String collectorNumber;

  final bool foilAvailable;
  final bool nonFoilAvailable;

  /// "normal" resolution image URL, or null when unavailable.
  final String? imageUri;

  /// Oracle text from the fuzzy-match response.  Null for tokens and
  /// card faces that don't have a standalone oracle entry.
  final String? oracleText;

  /// USD price from Scryfall, or null when unlisted.
  final double? priceUsd;

  /// EUR price from Scryfall, or null when unlisted.
  final double? priceEur;

  const ScryfallCard({
    required this.scryfallId,
    required this.name,
    required this.setCode,
    required this.setName,
    required this.collectorNumber,
    required this.foilAvailable,
    required this.nonFoilAvailable,
    this.imageUri,
    this.oracleText,
    this.priceUsd,
    this.priceEur,
  });

  // ---------------------------------------------------------------------------
  // Scryfall API parsing
  // ---------------------------------------------------------------------------

  /// Parse a single card object from the Scryfall REST API.
  ///
  /// Handles both single-face cards (`image_uris` at root) and double-faced
  /// cards (`image_uris` on `card_faces[0]`).
  factory ScryfallCard.fromScryfallJson(Map<String, dynamic> json) {
    // Double-faced cards nest image_uris under card_faces[0].
    final rootImages  = json['image_uris'] as Map<String, dynamic>?;
    final faceImages  = ((json['card_faces'] as List<dynamic>?)?.firstOrNull
                            as Map<String, dynamic>?)?['image_uris']
                        as Map<String, dynamic>?;
    final imageUris   = rootImages ?? faceImages;

    final prices = json['prices'] as Map<String, dynamic>?;

    return ScryfallCard(
      scryfallId:       json['id']               as String,
      name:             json['name']             as String,
      setCode:          json['set']              as String,
      setName:          json['set_name']         as String,
      collectorNumber:  json['collector_number'] as String,
      foilAvailable:    json['foil']             as bool? ?? false,
      nonFoilAvailable: json['nonfoil']          as bool? ?? true,
      imageUri:         imageUris?['normal']     as String?,
      oracleText:       json['oracle_text']      as String?,
      priceUsd:         double.tryParse(prices?['usd']?.toString() ?? ''),
      priceEur:         double.tryParse(prices?['eur']?.toString() ?? ''),
    );
  }

  // ---------------------------------------------------------------------------
  // Local storage serialisation
  // ---------------------------------------------------------------------------

  factory ScryfallCard.fromJson(Map<String, dynamic> json) {
    return ScryfallCard(
      scryfallId:       json['scryfall_id']        as String,
      name:             json['name']               as String,
      setCode:          json['set_code']           as String,
      setName:          json['set_name']           as String,
      collectorNumber:  json['collector_number']   as String,
      foilAvailable:    json['foil_available']     as bool,
      nonFoilAvailable: json['non_foil_available'] as bool,
      imageUri:         json['image_uri']          as String?,
      oracleText:       json['oracle_text']        as String?,
      priceUsd:         (json['price_usd'] as num?)?.toDouble(),
      priceEur:         (json['price_eur'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'scryfall_id':        scryfallId,
        'name':               name,
        'set_code':           setCode,
        'set_name':           setName,
        'collector_number':   collectorNumber,
        'foil_available':     foilAvailable,
        'non_foil_available': nonFoilAvailable,
        if (imageUri   != null) 'image_uri':   imageUri,
        if (oracleText != null) 'oracle_text': oracleText,
        if (priceUsd   != null) 'price_usd':   priceUsd,
        if (priceEur   != null) 'price_eur':   priceEur,
      };
}
