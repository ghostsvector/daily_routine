import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root service providers — one instance of each SDK service, shared by all
/// features. Feature-specific providers (auth state, task streams, etc.)
/// build on top of these rather than constructing services themselves.
final authServiceProvider = Provider<AuthService>((ref) => FirebaseAuthService());

final routineRepositoryProvider = Provider<RoutineRepositoryService>(
  (ref) => FirestoreRoutineRepositoryService(),
);

final blockedAppsRepositoryProvider = Provider<BlockedAppsRepositoryService>(
  (ref) => FirestoreBlockedAppsRepositoryService(),
);

final appBlockerProvider = Provider<AppBlockerService>(
  (ref) => AppBlockerService.instance,
);

final appUsageTrackerProvider = Provider<AppUsageTrackerService>(
  (ref) => AppUsageTrackerService.instance,
);

final activityRepositoryProvider = Provider<ActivityRepositoryService>(
  (ref) => FirestoreActivityRepositoryService(),
);

/// Initialized (async) in `main()` and supplied via `ProviderScope(overrides:
/// ...)`, since notification-channel setup must happen before first use.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in main() with an '
    'initialized NotificationService.',
  );
});

/// Overridden in `main()` with the same instance already wired up to
/// FlutterError.onError/runZonedGuarded, so app code that wants to record a
/// handled (non-fatal) error uses the identical reporter global crashes go
/// through.
final crashReportingServiceProvider = Provider<CrashReportingService>((ref) {
  throw UnimplementedError(
    'crashReportingServiceProvider must be overridden in main() with an '
    'initialized CrashReportingService.',
  );
});
