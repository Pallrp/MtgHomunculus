import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../models/scryfall_card.dart';

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Thrown when the Scryfall API returns an unexpected HTTP status.
class ScryfallException implements Exception {
  final int    statusCode;
  final String message;

  const ScryfallException(this.statusCode, this.message);

  @override
  String toString() => 'ScryfallException($statusCode): $message';
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Thin wrapper around the public Scryfall REST API.
///
/// All methods are static — no instance needed.
///
/// Rate limiting: Scryfall asks for ~75 ms between requests.  A shared
/// static timestamp ([_lastRequest]) enforces an 80 ms minimum gap across
/// all call sites automatically.
///
/// Network errors (SocketException, TimeoutException, …) are not caught
/// here — they propagate to the caller (the scan pipeline or UI layer).
class ScryfallClient {
  ScryfallClient._();

  static const _host    = 'api.scryfall.com';
  static const _minGap  = Duration(milliseconds: 80);
  static const _headers = {
    'User-Agent': 'MtgHomunculus/1.0',
    'Accept':     'application/json',
  };

  static DateTime? _lastRequest;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fuzzy card-name lookup — `GET /cards/named?fuzzy={text}`.
  ///
  /// Returns the best-matching [ScryfallCard] on success (HTTP 200).
  /// Returns **null** when no card matches (HTTP 404).
  /// Throws [ScryfallException] for any other non-200 status.
  static Future<ScryfallCard?> namedFuzzy(String text) async {
    final uri = Uri.https(_host, '/cards/named', {'fuzzy': text});
    final res = await _get(uri);

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      final msg = _detail(res);
      AppLogger.w('Scryfall namedFuzzy(${res.statusCode}): $msg — query: "$text"');
      throw ScryfallException(res.statusCode, msg);
    }

    return ScryfallCard.fromScryfallJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// All English printings of a card — follows Scryfall pagination.
  ///
  /// Query: `GET /cards/search?q="<name>"&unique=prints&lang=en`
  ///
  /// Returns an empty list when Scryfall has no printings (HTTP 404).
  /// Results are ordered newest-first (Scryfall default for `order=released
  /// &dir=desc`).
  /// Throws [ScryfallException] for any other non-200 status.
  static Future<List<ScryfallCard>> allPrintings(String name) async {
    final cards = <ScryfallCard>[];

    // Exact-name search: `!"Card Name"` — the `!` forces an exact match.
    Uri? uri = Uri.https(_host, '/cards/search', {
      'q':      '!"$name"',
      'unique': 'prints',
      'lang':   'en',
      'order':  'released',
      'dir':    'desc',
    });

    while (uri != null) {
      final res = await _get(uri);

      if (res.statusCode == 404) break;
      if (res.statusCode != 200) {
        final msg = _detail(res);
        AppLogger.w('Scryfall allPrintings(${res.statusCode}): $msg — query: "$name"');
        throw ScryfallException(res.statusCode, msg);
      }

      final body    = jsonDecode(res.body) as Map<String, dynamic>;
      final data    = body['data'] as List<dynamic>;
      final hasMore = body['has_more'] as bool? ?? false;
      final nextUrl = body['next_page'] as String?;

      cards.addAll(
        data.map((e) => ScryfallCard.fromScryfallJson(e as Map<String, dynamic>)),
      );

      uri = (hasMore && nextUrl != null) ? Uri.parse(nextUrl) : null;
    }

    return cards;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Issues a GET request after honouring the inter-request rate limit.
  static Future<http.Response> _get(Uri uri) async {
    await _throttle();
    AppLogger.d('Scryfall GET $uri');
    final res = await http.get(uri, headers: _headers);
    AppLogger.d('Scryfall ${res.statusCode} ${uri.path}');
    return res;
  }

  /// Enforces the minimum gap between consecutive Scryfall requests.
  static Future<void> _throttle() async {
    final last = _lastRequest;
    final now  = DateTime.now();
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < _minGap) await Future.delayed(_minGap - elapsed);
    }
    _lastRequest = DateTime.now();
  }

  /// Extract a human-readable message from a Scryfall error response body.
  static String _detail(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['details'] as String? ??
             body['warnings']?.toString() ??
             res.reasonPhrase ??
             'unknown error';
    } catch (_) {
      return res.reasonPhrase ?? 'unknown error';
    }
  }
}
