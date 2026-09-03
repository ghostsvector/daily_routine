import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/murthy_repository.dart';
import 'murthy_firebase_bootstrap.dart';
import 'murthy_voice_service.dart';

/// Keeps [MurthyVoiceService] alive per-platform:
///
/// - Android/iOS: apps get suspended or killed once backgrounded, so
///   staying alive needs a real OS-level background service —
///   `flutter_background_service`, which on Android runs as a foreground
///   service (persistent notification, per Android's rules) and on iOS
///   relies on the `audio` background mode declared in Info.plist. Neither
///   platform lets a third-party app listen forever with total certainty —
///   the OS can still reclaim it under memory pressure.
/// - Desktop (Linux/macOS/Windows): `flutter_background_service` has no
///   desktop implementation, but desktop apps also aren't suspended just
///   for losing focus — so this runs [MurthyVoiceService] directly in the
///   normal app process. It keeps listening as long as the app itself
///   hasn't been fully closed, minimized or not.
class MurthyBackgroundRunner {
  MurthyBackgroundRunner._();

  static MurthyVoiceService? _desktopService;

  static bool get _isMobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> start() async {
    if (_isMobile) {
      return _startMobile();
    }
    return _startDesktop();
  }

  static Future<void> stop() async {
    if (_isMobile) {
      FlutterBackgroundService().invoke('stopService');
      return;
    }
    await _desktopService?.stop();
    _desktopService = null;
  }

  static Future<bool> isRunning() async {
    if (_isMobile) {
      return FlutterBackgroundService().isRunning();
    }
    return _desktopService?.isRunning ?? false;
  }

  static Future<bool> _startDesktop() async {
    _desktopService ??= MurthyVoiceService(
      authService: FirebaseAuthService(),
      routineRepository: FirestoreRoutineRepositoryService(),
      murthyRepository: MurthyRepository(),
    );
    return _desktopService!.start();
  }

  static Future<bool> _startMobile() async {
    // flutter_background_service requires the Android notification channel
    // to already exist before configure() is called.
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _mobileNotificationChannelId,
            'Murthy voice assistant',
            description: 'Shown while "Hey Murthy" is listening in the background.',
            importance: Importance.low,
          ),
        );

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onMobileServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _mobileNotificationChannelId,
        initialNotificationTitle: 'Murthy',
        initialNotificationContent: 'Listening for "Hey Murthy"',
        foregroundServiceTypes: const [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(onForeground: _onMobileServiceStart, onBackground: _onIosBackground),
    );
    return service.startService();
  }
}

const _mobileNotificationChannelId = 'murthy_voice';

@pragma('vm:entry-point')
Future<void> _onMobileServiceStart(ServiceInstance serviceInstance) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureMurthyFirebaseReady();

  final voice = MurthyVoiceService(
    authService: FirebaseAuthService(),
    routineRepository: FirestoreRoutineRepositoryService(),
    murthyRepository: MurthyRepository(),
  );
  final started = await voice.start();
  if (!started) {
    serviceInstance.stopSelf();
    return;
  }

  serviceInstance.on('stopService').listen((_) async {
    await voice.stop();
    serviceInstance.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance serviceInstance) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
