import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../flavors/flavor_selector.dart';

/// Mirrors `main()`'s Firebase bootstrap, for code that runs outside the
/// normal widget tree and app lifecycle — the background-service isolate
/// the "Hey Murthy" wake-word listener runs in on Android/iOS, which gets
/// its own fresh Dart VM with none of `main()`'s setup done. Safe to call
/// more than once; each step no-ops if already done.
Future<void> ensureMurthyFirebaseReady() async {
  if (!dotenv.isInitialized) {
    await dotenv.load(
      fileName: '.env',
      overrideWithFiles: ['.env.local'],
      isOptional: true,
    );
  }

  final isLinuxDesktop =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  final options = getFirebaseOptions();
  if (isLinuxDesktop) {
    RestFirebaseConfig.configure(
      projectId: options.projectId,
      apiKey: options.apiKey,
    );
  } else if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}
