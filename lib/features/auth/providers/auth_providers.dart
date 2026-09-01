import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final authStateProvider = StreamProvider<AppUser>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// The current user, or [AppUser.empty] while auth state is still loading.
final currentUserProvider = Provider<AppUser>((ref) {
  return ref.watch(authStateProvider).valueOrNull ?? AppUser.empty;
});
