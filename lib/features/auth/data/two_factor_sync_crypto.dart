import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC for the TOTP secret at rest in Firestore — same reasoning
/// as Murthy's `MurthyCryptoService`: Firestore security rules already
/// restrict this document to its owning uid, but a 2FA secret is
/// sensitive enough (it's the entire second factor) to also not sit there
/// in plaintext, e.g. against a compromised admin-SDK key.
///
/// Unlike Murthy's key (generated once per device, never leaves it), this
/// key must exist on every device that should be able to verify codes for
/// the account — see [TwoFactorService] for the manual-pairing flow that
/// gets it there.
class TwoFactorSyncCrypto {
  const TwoFactorSyncCrypto();

  Map<String, String> encrypt(String plaintext, String base64Key) {
    final key = enc.Key.fromBase64(base64Key);
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final ciphertext = encrypter.encrypt(plaintext, iv: iv);
    return {'iv': iv.base64, 'data': ciphertext.base64};
  }

  String decrypt(Map<String, dynamic> stored, String base64Key) {
    final key = enc.Key.fromBase64(base64Key);
    final iv = enc.IV.fromBase64(stored['iv'] as String);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt64(stored['data'] as String, iv: iv);
  }

  String generateKey() => enc.Key.fromSecureRandom(32).base64;
}
