import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/two_factor_service.dart';
import 'auth_providers.dart';

final twoFactorServiceProvider = Provider<TwoFactorService>((ref) => TwoFactorService());

/// Whether 2FA is enrolled for the *currently signed-in* account —
/// persisted per-uid (OS keystore), survives app restarts. Re-read on
/// demand rather than streamed, since it only changes from the setup
/// screen itself (which invalidates this after enroll/disable).
final twoFactorEnabledProvider = FutureProvider<bool>((ref) {
  final uid = ref.watch(currentUserProvider).uid;
  return ref.watch(twoFactorServiceProvider).isEnabled(uid);
});

/// Whether the account has 2FA enabled on *some* device, even if not this
/// one — the setup screen uses this to offer "pair this device" instead
/// of "set up 2FA" when another device already enrolled.
final twoFactorHasRemoteEnrollmentProvider = FutureProvider<bool>((ref) {
  final uid = ref.watch(currentUserProvider).uid;
  return ref.watch(twoFactorServiceProvider).hasRemoteEnrollment(uid);
});

/// Whether the *current app session* has passed the TOTP challenge —
/// intentionally NOT persisted: a fresh app launch always re-challenges,
/// which is the point of a second factor. Reset to false on sign-out via
/// the router's redirect logic re-reading auth state.
final twoFactorSessionVerifiedProvider = StateProvider<bool>((ref) => false);
