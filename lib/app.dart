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
    );
  }
}
