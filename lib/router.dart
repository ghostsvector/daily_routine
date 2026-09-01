import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/providers/auth_providers.dart';
import 'features/auth/screens/sign_in_screen.dart';
import 'features/auth/screens/sign_up_screen.dart';
import 'features/blocking/screens/blocked_apps_screen.dart';
import 'features/blocking/screens/focus_session_screen.dart';
import 'features/routines/screens/edit_task_screen.dart';
import 'features/routines/screens/home_screen.dart';
import 'features/settings/screens/settings_screen.dart';

/// Notifies `go_router` whenever Firebase auth state changes, without
/// tearing down and recreating the [GoRouter] itself (which would lose the
/// navigation stack).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) => notifyListeners());
  }
}

final _authRefreshNotifierProvider = Provider<_AuthRefreshNotifier>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_authRefreshNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authValue = ref.read(authStateProvider);
      if (!authValue.hasValue) return null;
      final isLoggedIn = authValue.value?.isNotEmpty ?? false;
      final isAuthRoute =
          state.matchedLocation == '/sign-in' || state.matchedLocation == '/sign-up';
      if (!isLoggedIn && !isAuthRoute) return '/sign-in';
      if (isLoggedIn && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (context, state) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (context, state) => const SignUpScreen()),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/task/new',
        builder: (context, state) => const EditTaskScreen(),
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) => EditTaskScreen(taskId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/blocked-apps',
        builder: (context, state) => const BlockedAppsScreen(),
      ),
      GoRoute(
        path: '/focus-session',
        builder: (context, state) => FocusSessionScreen(task: state.extra as RoutineTask),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    ],
  );
});
