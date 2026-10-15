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

  /// As read from Deckbox's own page — empty if the page did not name the user,
  /// which the spike screen's account guard treats as "not the test account".
  final String username;

  final Map<String, String> cookies;
  final DateTime savedAt;

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

/// The Deckbox session in secure storage — encrypted with a key the Android
/// Keystore holds, so the file reads as ciphertext even where `run-as` can
/// reach it.
///
/// **One session, one key, for now.** M2 keys it by account id once the
/// `ExternalAccounts` table exists; until the spikes have settled the model,
/// there is nothing to key it by.
///
/// The storage files are excluded from Android Auto Backup in
/// `res/xml/backup_rules.xml` and `data_extraction_rules.xml`: a restored copy
/// would be ciphertext whose key stayed behind on the old phone.
class SessionStore {
  SessionStore._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'deckbox_session';

  static Future<DeckboxSession?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return DeckboxSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Unreadable reads as signed out — the user logs in again. The error
      // itself is logged by type only: its message could quote stored data.
      AppLogger.w('Deckbox session unreadable (${e.runtimeType}); treating as signed out');
      return null;
    }
  }

  static Future<void> save(DeckboxSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  static Future<void> clear() => _storage.delete(key: _key);
}
