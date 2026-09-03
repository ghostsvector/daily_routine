import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts every Murthy document (daily protocols, daily progress/summary)
/// before it leaves the device. Firestore — and anyone who can read the
/// project's Firestore data, including us, since this is an open-source
/// repo other people run their own copy of — only ever sees AES ciphertext,
/// never the plaintext content.
///
/// The AES key is generated once per install and kept in the OS keystore
/// (`flutter_secure_storage`, i.e. Android Keystore / iOS Keychain /
/// libsecret) — it never touches Firestore, never gets logged, and is never
/// committed to the repo. Signing in on a new device starts a fresh key, so
/// older Murthy entries stay unreadable there; that's the tradeoff for never
/// syncing the key itself anywhere.
class MurthyCryptoService {
  MurthyCryptoService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyStorageKey = 'murthy_encryption_key_v1';

  final FlutterSecureStorage _storage;
  enc.Key? _cachedKey;

  Future<enc.Key> _getOrCreateKey() async {
    final cached = _cachedKey;
    if (cached != null) return cached;

    var stored = await _storage.read(key: _keyStorageKey);
    if (stored == null) {
      stored = enc.Key.fromSecureRandom(32).base64;
      await _storage.write(key: _keyStorageKey, value: stored);
    }
    final key = enc.Key.fromBase64(stored);
    _cachedKey = key;
    return key;
  }

  /// Encrypts [json] into the shape stored directly as a Firestore document.
  Future<Map<String, dynamic>> encryptJson(Map<String, dynamic> json) async {
    final key = await _getOrCreateKey();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final ciphertext = encrypter.encrypt(jsonEncode(json), iv: iv);
    return {'iv': iv.base64, 'data': ciphertext.base64};
  }

  /// Reverses [encryptJson] given a Firestore document's raw data.
  Future<Map<String, dynamic>> decryptJson(Map<String, dynamic> stored) async {
    final key = await _getOrCreateKey();
    final iv = enc.IV.fromBase64(stored['iv'] as String);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final plaintext = encrypter.decrypt64(stored['data'] as String, iv: iv);
    return jsonDecode(plaintext) as Map<String, dynamic>;
  }

  /// The raw base64 AES-256 key, for deliberately copying this device's
  /// Murthy data key out to another trusted decryptor (e.g. a local
  /// MCP/analysis server you run yourself). Anyone with this string can
  /// read and forge every Murthy document in your Firestore project —
  /// treat it exactly like a password, never commit it, and only export it
  /// for a tool you're setting up yourself.
  Future<String> exportKeyBase64() async {
    final key = await _getOrCreateKey();
    return key.base64;
  }
}
