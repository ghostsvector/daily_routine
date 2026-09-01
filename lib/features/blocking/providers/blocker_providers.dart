import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';

/// Apps/processes discoverable on this device that could be added to a
/// task's blocklist.
final blockableTargetsProvider = FutureProvider<List<BlockedApp>>((ref) {
  return ref.watch(appBlockerProvider).getBlockableTargets();
});

final hasBlockPermissionProvider = FutureProvider<bool>((ref) {
  return ref.watch(appBlockerProvider).hasPermission();
});

/// The user's saved blocklist selection, synced across devices via Firestore.
final savedBlockedAppsProvider = StreamProvider<List<BlockedApp>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref.watch(blockedAppsRepositoryProvider).watchBlockedApps(user.uid);
});
