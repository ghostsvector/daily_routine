import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'flavors/flavor_selector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `.env.local` (untracked, personal) overrides `.env` (shared defaults),
  // matching the convention most JS tooling uses. Both are optional.
  await dotenv.load(
    fileName: '.env',
    overrideWithFiles: ['.env.local'],
    isOptional: true,
  );

  // firebase_core has no Linux desktop implementation — Firebase.initializeApp()
  // itself would throw there (no platform channel to answer it), so every
  // Firebase-backed SDK service dispatches internally to a REST-based
  // implementation on Linux instead of the native plugin (see
  // daily_routine_sdk's FirebaseAuthService/FirestoreRoutineRepositoryService/
  // FirestoreBlockedAppsRepositoryService). That REST path needs the raw
  // project id/API key up front, via RestFirebaseConfig — set once, here,
  // instead of Firebase.initializeApp(), before any Firebase-backed SDK
  // class gets constructed below.
  final isLinuxDesktop = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  Object? firebaseInitError;
  try {
    final options = getFirebaseOptions();
    if (isLinuxDesktop) {
      RestFirebaseConfig.configure(projectId: options.projectId, apiKey: options.apiKey);
    } else {
      await Firebase.initializeApp(options: options);
    }
  } catch (e) {
    firebaseInitError = e;
  }

  final notificationService = LocalNotificationService(
    config: const LocalNotificationChannelConfig(
      channelId: 'routine_reminders',
      channelName: 'Routine reminders',
      channelDescription: 'Reminders for your scheduled routine tasks.',
    ),
  );
  if (firebaseInitError == null) {
    await notificationService.initialize();
  }

  runApp(
    ProviderScope(
      overrides: [notificationServiceProvider.overrideWithValue(notificationService)],
      child: firebaseInitError == null
          ? const DailyRoutineApp()
          : _FirebaseNotConfiguredApp(error: firebaseInitError),
    ),
  );
}

/// Shown instead of crashing when Firebase hasn't been configured yet (no
/// `.env`, or `flutterfire configure` hasn't been run), so `flutter run`
/// still produces something useful out of the box.
class _FirebaseNotConfiguredApp extends StatelessWidget {
  const _FirebaseNotConfiguredApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Firebase is not configured yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Copy .env.example to .env and fill in your Firebase project '
                  'values (or run `flutterfire configure`), then restart.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text('$error', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
