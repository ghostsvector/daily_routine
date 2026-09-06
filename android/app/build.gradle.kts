plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kasinadhsarma.dailyroutine"
    // 37: floor required by flutter_secure_storage; flutter.compileSdkVersion
    // (36) isn't high enough yet.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.kasinadhsarma.dailyroutine"
        // 24: floor required by the daily_routine_sdk plugin (UsageStatsManager
        // app-blocking on Android).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Mirrors the Dart-side FLAVOR dart-define (see lib/flavors/flavor_selector.dart)
    // as real Gradle product flavors, so internal and external are genuinely
    // separate installable apps — not just a different title/banner in the
    // same APK. "external" keeps the app's original applicationId so the
    // existing installed app and its Firebase Android app registration are
    // untouched; "internal" gets its own applicationId + its own Firebase
    // Android app registration in google-services.json (added via
    // `firebase apps:create ANDROID`), since the google-services Gradle
    // plugin hard-fails the build if a flavor's applicationId has no
    // matching client entry there.
    flavorDimensions += "environment"
    productFlavors {
        create("external") {
            dimension = "environment"
        }
        create("internal") {
            dimension = "environment"
            applicationId = "com.kasinadhsarma.dailyroutine.internal"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
