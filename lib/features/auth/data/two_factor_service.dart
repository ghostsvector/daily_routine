import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-level TOTP (RFC 6238) second factor on top of Firebase Auth sign-in.
///
/// Firebase's own multi-factor auth requires the Identity Platform upgrade
/// and is primarily SMS-oriented — overkill (and not free-tier) for a
/// personal-use app. This instead keeps the secret entirely on-device in
/// the OS keystore, the same pattern as Murthy's encryption key
/// (`MurthyCryptoService`): never synced, never sent anywhere, works
/// identically on every platform including the Linux REST auth path.
///
/// Enrollment is two-step on purpose: [beginEnrollment] generates and
/// stores a *pending* secret without enabling anything, and
/// [confirmEnrollment] only flips the "enabled" flag after the user proves
/// they actually captured it correctly in their authenticator app. Skipping
/// that check would let someone lock themselves out with a secret their
/// authenticator never actually saved.
///
/// Every method takes [uid] and scopes its storage keys by it — 2FA is a
/// property of the signed-in *account*, not the device. Without this, a
/// second Firebase account signing into the same device install would
/// share (and could satisfy) the first account's 2FA challenge, which
/// defeats the entire point of a second factor.
class TwoFactorService {
  TwoFactorService({FlutterSecureStorage? storage, TotpService? totp})
    : _storage = storage ?? const FlutterSecureStorage(),
      _totp = totp ?? const TotpService();

  final FlutterSecureStorage _storage;
  final TotpService _totp;

  String _secretKey(String uid) => 'totp_secret_v1_$uid';
  String _enabledKey(String uid) => 'totp_enabled_v1_$uid';

  Future<bool> isEnabled(String uid) async {
    final value = await _storage.read(key: _enabledKey(uid));
    return value == 'true';
  }

  /// Generates a new secret and stores it (not yet enabled) — returns the
  /// otpauth:// URI/secret for the setup screen to display.
  Future<String> beginEnrollment({required String uid, required String accountEmail}) async {
    final secret = _totp.generateSecret();
    await _storage.write(key: _secretKey(uid), value: secret);
    return _totp.buildProvisioningUri(base32Secret: secret, accountName: accountEmail);
  }

  Future<String?> pendingSecret(String uid) => _storage.read(key: _secretKey(uid));

  /// Verifies [code] against the pending secret and, if valid, marks 2FA
  /// enabled. Returns false (without enabling anything) on a wrong code.
  Future<bool> confirmEnrollment(String uid, String code) async {
    final secret = await pendingSecret(uid);
    if (secret == null) return false;
    if (!_totp.verifyCode(secret, code)) return false;
    await _storage.write(key: _enabledKey(uid), value: 'true');
    return true;
  }

  /// Verifies [code] for an already-enabled 2FA against the current secret
  /// — the login-time challenge.
  Future<bool> verify(String uid, String code) async {
    final secret = await pendingSecret(uid);
    if (secret == null) return false;
    return _totp.verifyCode(secret, code);
  }

  /// Disables 2FA and erases the secret. Requires a valid current code so
  /// disabling isn't possible from an unlocked-but-not-yet-challenged
  /// session alone.
  Future<bool> disable(String uid, String code) async {
    final valid = await verify(uid, code);
    if (!valid) return false;
    await _storage.delete(key: _secretKey(uid));
    await _storage.delete(key: _enabledKey(uid));
    return true;
  }
}
