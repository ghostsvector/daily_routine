import 'dart:async';

import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';

final activityTrackingSupportedProvider = FutureProvider<bool>((ref) {
  return ref.watch(appUsageTrackerProvider).isSupported();
});

final hasUsageTrackingPermissionProvider = FutureProvider<bool>((ref) {
  return ref.watch(appUsageTrackerProvider).hasPermission();
});

/// Recent app-usage / browser activity, synced across devices via
/// Firestore — newest first.
///
/// `autoDispose`: on Linux this polls Firestore's REST API on a timer (see
/// `RestActivityRepositoryService`) — without autoDispose, a plain
/// `StreamProvider` never tears down once first watched, so the poll loop
/// would keep hitting Firestore for as long as the app process runs, even
/// after navigating away from this screen. Letting it dispose when nothing
/// is watching it means reads only happen while this screen is actually
/// open.
final recentActivityProvider = StreamProvider.autoDispose<List<ActivityEvent>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref.watch(activityRepositoryProvider).watchRecentActivity(user.uid);
});

/// Starts/stops the on-device tracker and forwards each completed session
/// to Firestore. `state` is whether tracking is currently running.
class ActivityTrackingController extends StateNotifier<bool> {
  ActivityTrackingController(this._ref) : super(false);

  final Ref _ref;
  StreamSubscription<AppUsageEvent>? _subscription;

  Future<void> start() async {
    final tracker = _ref.read(appUsageTrackerProvider);
    await tracker.startTracking();

    final repo = _ref.read(activityRepositoryProvider);
    final user = _ref.read(currentUserProvider);
    await _subscription?.cancel();
    _subscription = tracker.events.listen((event) {
      repo.logAppUsage(user.uid, event);
    });
    state = true;
  }

  Future<void> stop() async {
    await _ref.read(appUsageTrackerProvider).stopTracking();
    await _subscription?.cancel();
    _subscription = null;
    state = false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final activityTrackingControllerProvider =
    StateNotifierProvider<ActivityTrackingController, bool>(
      (ref) => ActivityTrackingController(ref),
    );
