import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/two_factor_service.dart';

final twoFactorServiceProvider = Provider<TwoFactorService>((ref) => TwoFactorService());

/// Whether 2FA is enrolled at all — persisted (OS keystore), survives app
/// restarts. Re-read on demand rather than streamed, since it only changes
/// from the setup screen itself (which invalidates this after enroll/disable).
final twoFactorEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(twoFactorServiceProvider).isEnabled();
});

/// Whether the *current app session* has passed the TOTP challenge —
/// intentionally NOT persisted: a fresh app launch always re-challenges,
/// which is the point of a second factor. Reset to false on sign-out via
/// the router's redirect logic re-reading auth state.
final twoFactorSessionVerifiedProvider = StateProvider<bool>((ref) => false);
