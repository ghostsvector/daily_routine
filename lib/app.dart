import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/providers/auth_providers.dart';
import 'flavors/flavor_selector.dart';
import 'router.dart';

class DailyRoutineApp extends ConsumerWidget {
  const DailyRoutineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Tags crash reports with the signed-in user's uid, so reports from the
    // same account can be correlated in the Crashlytics console.
    ref.listen(currentUserProvider, (previous, next) {
      ref.read(crashReportingServiceProvider).setUserId(next.isEmpty ? null : next.uid);
    });

    return MaterialApp.router(
      title: getAppTitle(),
      // Flutter's own debug banner tracks build mode (debug vs. release),
      // not flavor — it's off here so a release-mode internal build still
      // needs its own way to say "this isn't the build real users have".
      // The banner below is that: tied to FLAVOR, shown regardless of
      // build mode, so an internal build is never mistaken for external.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        if (flavor != 'internal' || child == null) return child ?? const SizedBox.shrink();
        return Banner(
          message: 'INTERNAL',
          location: BannerLocation.topEnd,
          color: Colors.red.shade700,
          child: child,
        );
      },
    );
  }
}
