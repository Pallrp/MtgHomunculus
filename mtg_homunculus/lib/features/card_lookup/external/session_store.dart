import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/logging/app_logger.dart';

/// A signed-in Deckbox session: the cookies that carry it, and whose it is.
///
/// **Never the password.** The login dialog uses it for one request and drops
/// it; what survives an app restart is only this.
class DeckboxSession {
  const DeckboxSession({
    required this.username,
    required this.cookies,
    required this.savedAt,
  });

  /// As read from Deckbox's own page (the Friends link, D1).
  final String username;

  final Map<String, String> cookies;

  /// When the session was signed in — not when it was last refreshed.
  final DateTime savedAt;

  /// The same session with the cookies a later request came back with.
  /// Deckbox reissues its session cookie on every response with a new
  /// six-month expiry (D1); saving it back is what keeps a used session alive.
  DeckboxSession withCookies(Map<String, String> fresh) =>
      DeckboxSession(username: username, cookies: fresh, savedAt: savedAt);

  Map<String, Object> toJson() => {
        'username': username,
        'cookies': cookies,
        'savedAt': savedAt.toIso8601String(),
      };

  static DeckboxSession fromJson(Map<String, dynamic> j) => DeckboxSession(
        username: j['username'] as String,
        cookies: (j['cookies'] as Map).cast<String, String>(),
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
}

/// Deckbox sessions in secure storage, **one per account** — encrypted with a
/// key the Android Keystore holds, so the file reads as ciphertext even where
/// `run-as` can reach it.
///
/// Keyed by the `ExternalAccounts` row id. The database knows an account
/// exists; only this knows how to sign in as it, and only on this phone.
///
/// The storage files are excluded from Android Auto Backup in
/// `res/xml/backup_rules.xml` and `data_extraction_rules.xml`: a restored copy
/// would be ciphertext whose key stayed behind on the old phone.
class SessionStore {
  SessionStore._();

  static const _storage = FlutterSecureStorage();
  static String _key(int accountId) => 'deckbox_session_$accountId';

  static Future<DeckboxSession?> load(int accountId) async {
    try {
      final raw = await _storage.read(key: _key(accountId));
      if (raw == null) return null;
      return DeckboxSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Unreadable reads as signed out — the user logs in again. The error
      // itself is logged by type only: its message could quote stored data.
      AppLogger.w('Deckbox session unreadable (${e.runtimeType}); treating as signed out');
      return null;
    }
  }

  static Future<void> save(int accountId, DeckboxSession session) =>
      _storage.write(key: _key(accountId), value: jsonEncode(session.toJson()));

  static Future<void> clear(int accountId) => _storage.delete(key: _key(accountId));
}
