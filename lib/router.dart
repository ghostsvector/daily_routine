import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/activity/screens/activity_screen.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/auth/providers/two_factor_providers.dart';
import 'features/auth/screens/sign_in_screen.dart';
import 'features/auth/screens/sign_up_screen.dart';
import 'features/auth/screens/two_factor_challenge_screen.dart';
import 'features/auth/screens/two_factor_setup_screen.dart';
import 'features/blocking/screens/blocked_apps_screen.dart';
import 'features/blocking/screens/focus_session_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/murthy/screens/murthy_screen.dart';
import 'features/routines/screens/edit_task_screen.dart';
import 'features/routines/screens/home_screen.dart';
import 'features/settings/screens/settings_screen.dart';

/// Notifies `go_router` whenever Firebase auth state, 2FA enrollment, or
/// this session's 2FA challenge result changes, without tearing down and
/// recreating the [GoRouter] itself (which would lose the navigation stack).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) {
      // A fresh sign-in always needs a fresh 2FA challenge — otherwise
      // signing out and back in within the same app session would skip it.
      final wasLoggedIn = previous?.value?.isNotEmpty ?? false;
      final isLoggedIn = next.value?.isNotEmpty ?? false;
      if (wasLoggedIn && !isLoggedIn) {
        ref.read(twoFactorSessionVerifiedProvider.notifier).state = false;
      }
      notifyListeners();
    });
    ref.listen(twoFactorEnabledProvider, (previous, next) => notifyListeners());
    ref.listen(twoFactorSessionVerifiedProvider, (previous, next) => notifyListeners());
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
          state.matchedLocation == '/sign-in' ||
          state.matchedLocation == '/sign-up';
      if (!isLoggedIn) return isAuthRoute ? null : '/sign-in';
      if (isAuthRoute) return '/';

      // Past this point the user is signed in — gate on the TOTP second
      // factor, if enrolled. `valueOrNull` treats "still loading" as "not
      // enabled yet" rather than blocking navigation on every route change.
      final twoFactorEnabled = ref.read(twoFactorEnabledProvider).valueOrNull ?? false;
      final twoFactorVerified = ref.read(twoFactorSessionVerifiedProvider);
      final isChallengeRoute = state.matchedLocation == '/2fa';
      if (twoFactorEnabled && !twoFactorVerified) {
        return isChallengeRoute ? null : '/2fa';
      }
      if (isChallengeRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/task/new',
        builder: (context, state) => const EditTaskScreen(),
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) =>
            EditTaskScreen(taskId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/blocked-apps',
        builder: (context, state) => const BlockedAppsScreen(),
      ),
      GoRoute(
        path: '/focus-session',
        builder: (context, state) =>
            FocusSessionScreen(task: state.extra as RoutineTask),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/activity',
        builder: (context, state) => const ActivityScreen(),
      ),
      GoRoute(
        path: '/murthy',
        builder: (context, state) => const MurthyScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/2fa',
        builder: (context, state) => const TwoFactorChallengeScreen(),
      ),
      GoRoute(
        path: '/2fa-setup',
        builder: (context, state) => const TwoFactorSetupScreen(),
      ),
    ],
  );
});
