import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'two_factor_remote_store.dart';
import 'two_factor_sync_crypto.dart';

/// App-level TOTP (RFC 6238) second factor on top of Firebase Auth sign-in.
///
/// Firebase's own multi-factor auth requires the Identity Platform upgrade
/// and is primarily SMS-oriented — overkill (and not free-tier) for a
/// personal-use app. The TOTP secret itself lives in the OS keystore on
/// each device that can verify codes, but — unlike Murthy's encryption
/// key, which is deliberately device-only — a second factor has to work
/// from every device you sign into, or it isn't actually protecting the
/// account. So the secret is *also* kept, encrypted, in Firestore
/// (`users/{uid}/meta/twoFactor`) for other devices to pull down.
///
/// The catch: decrypting that Firestore record needs a key too, and that
/// key can't just live in Firestore next to the ciphertext (that would
/// defeat the point). So pairing a new device is a manual step — copy
/// this device's "sync key" ([exportSyncKey]) to the new one and call
/// [importFromSyncKey] there — the same manual-transfer pattern Murthy's
/// "Export encryption key" already uses, for the same reason: no secret
/// this sensitive gets synced automatically without the owner deliberately
/// choosing to.
///
/// Enrollment is two-step on purpose: [beginEnrollment] generates and
/// stores a *pending* secret without enabling anything, and
/// [confirmEnrollment] only flips the "enabled" flag (and uploads the
/// sync record) after the user proves they actually captured it correctly
/// in their authenticator app.
///
/// Every method takes [uid] and scopes its storage keys by it — 2FA is a
/// property of the signed-in *account*, not the device.
class TwoFactorService {
  TwoFactorService({
    FlutterSecureStorage? storage,
    TotpService? totp,
    TwoFactorRemoteStore? remote,
    TwoFactorSyncCrypto? crypto,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _totp = totp ?? const TotpService(),
       _remote = remote ?? TwoFactorRemoteStore(),
       _crypto = crypto ?? const TwoFactorSyncCrypto();

  final FlutterSecureStorage _storage;
  final TotpService _totp;
  final TwoFactorRemoteStore _remote;
  final TwoFactorSyncCrypto _crypto;

  String _secretKey(String uid) => 'totp_secret_v1_$uid';
  String _enabledKey(String uid) => 'totp_enabled_v1_$uid';
  String _syncKeyKey(String uid) => 'totp_sync_key_v1_$uid';

  Future<bool> isEnabled(String uid) async {
    final value = await _storage.read(key: _enabledKey(uid));
    return value == 'true';
  }

  /// Whether this *account* has 2FA enabled on some device, even if not
  /// this one — used to show "pair this device" instead of "set up 2FA"
  /// when another device already enrolled.
  Future<bool> hasRemoteEnrollment(String uid) async {
    return await _remote.read(uid) != null;
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
  /// enabled and uploads the encrypted sync record so other devices can
  /// pair to it. Returns false (without enabling anything) on a wrong code.
  Future<bool> confirmEnrollment(String uid, String code) async {
    final secret = await pendingSecret(uid);
    if (secret == null) return false;
    if (!_totp.verifyCode(secret, code)) return false;

    final syncKey = await _getOrCreateSyncKey(uid);
    await _remote.write(uid, _crypto.encrypt(secret, syncKey));
    await _storage.write(key: _enabledKey(uid), value: 'true');
    return true;
  }

  /// Verifies [code] for an already-enabled 2FA against the current secret
  /// — the login-time challenge. Checked locally, never round-trips to
  /// Firestore, so verification still works offline.
  Future<bool> verify(String uid, String code) async {
    final secret = await pendingSecret(uid);
    if (secret == null) return false;
    return _totp.verifyCode(secret, code);
  }

  /// Disables 2FA everywhere: requires a valid current code (so disabling
  /// isn't possible from an unlocked-but-not-yet-challenged session
  /// alone), then clears this device's copy and the shared Firestore
  /// record, so no other device can still use it either.
  Future<bool> disable(String uid, String code) async {
    final valid = await verify(uid, code);
    if (!valid) return false;
    await _storage.delete(key: _secretKey(uid));
    await _storage.delete(key: _enabledKey(uid));
    await _storage.delete(key: _syncKeyKey(uid));
    await _remote.delete(uid);
    return true;
  }

  /// This device's sync key, to copy into [importFromSyncKey] on another
  /// device. Null if 2FA isn't enabled on this device (or hasn't been
  /// migrated via [ensureSynced] yet).
  Future<String?> exportSyncKey(String uid) => _storage.read(key: _syncKeyKey(uid));

  /// Pairs this device to an account-wide 2FA enrollment set up elsewhere:
  /// decrypts the Firestore-stored secret with [syncKey] and, on success,
  /// enables 2FA locally here too. Returns false if there's no remote
  /// record, or [syncKey] doesn't decrypt it (wrong key).
  Future<bool> importFromSyncKey(String uid, String syncKey) async {
    final record = await _remote.read(uid);
    if (record == null) return false;

    final String secret;
    try {
      secret = _crypto.decrypt(record, syncKey);
    } catch (_) {
      return false;
    }

    await _storage.write(key: _secretKey(uid), value: secret);
    await _storage.write(key: _syncKeyKey(uid), value: syncKey);
    await _storage.write(key: _enabledKey(uid), value: 'true');
    return true;
  }

  /// Backfills the Firestore sync record for a device that enrolled before
  /// cross-device sync existed (local secret + enabled flag present, but
  /// no sync key/remote record yet). A no-op once already synced. Safe to
  /// call unconditionally whenever the setup screen loads.
  Future<void> ensureSynced(String uid) async {
    if (!await isEnabled(uid)) return;
    if (await _storage.read(key: _syncKeyKey(uid)) != null) return;

    final secret = await pendingSecret(uid);
    if (secret == null) return;

    final syncKey = await _getOrCreateSyncKey(uid);
    await _remote.write(uid, _crypto.encrypt(secret, syncKey));
  }

  Future<String> _getOrCreateSyncKey(String uid) async {
    final existing = await _storage.read(key: _syncKeyKey(uid));
    if (existing != null) return existing;
    final generated = _crypto.generateKey();
    await _storage.write(key: _syncKeyKey(uid), value: generated);
    return generated;
  }
}
