// Centralized flavor-based selection for Firebase, app title, and more.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'external/firebase_options.dart' as external_options;
import 'internal/firebase_options.dart' as internal_options;
import 'external/app_strings.dart' as external_strings;
import 'internal/app_strings.dart' as internal_strings;

const String flavor = String.fromEnvironment(
  'FLAVOR',
  defaultValue: 'external',
);

FirebaseOptions getFirebaseOptions() {
  switch (flavor) {
    case 'external':
      return external_options.DefaultFirebaseOptions.currentPlatform;
    case 'internal':
      return internal_options.DefaultFirebaseOptions.currentPlatform;
    default:
      throw UnsupportedError('Unknown flavor: $flavor');
  }
}

String getAppTitle() {
  switch (flavor) {
    case 'external':
      return external_strings.getAppTitle();
    case 'internal':
      return internal_strings.getAppTitle();
    default:
      throw UnsupportedError('Unknown flavor: $flavor');
  }
}
