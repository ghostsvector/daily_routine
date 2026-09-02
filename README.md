# Daily Routine

[![CI](https://github.com/kasinadhsarma/daily_routine/actions/workflows/ci.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine/actions/workflows/ci.yml)
[![Release](https://github.com/kasinadhsarma/daily_routine/actions/workflows/release.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Flutter app for scheduling a daily routine, running focused work sessions
with distracting apps blocked, and tracking your own activity (app usage,
browsing) across devices — so you can actually see how a day went, not just
plan it.

## Features

- **Routines** — scheduled tasks with reminders, alarm-style full-screen
  notifications, and repeat rules (daily/weekdays/weekends/custom days).
- **Focus sessions & app blocking** — attach a blocklist to a task; while
  it's running, blocked apps are kicked to the foreground and back out
  (Android: a foreground service polling `UsageStatsManager`; desktop:
  process polling — see `daily_routine_sdk`'s README for the details and
  caveats).
- **Activity tracking**, synced to the same Firestore account across every
  surface:
  - **Android** — on-device app usage (`Settings → Activity`).
  - **Desktop** (Linux/Windows/macOS) — focused window (app + title), which
    is usually the most useful signal: the file open in an editor, the
    video playing, the browser tab.
  - **Browser** — a companion Chrome extension in [`chrome_extension/`](chrome_extension/)
    logs tab sessions and YouTube watch activity.
- **Auth** — email/password or Google sign-in, synced via Firebase.

## Project layout

- `lib/features/` — `routines/`, `blocking/`, `activity/`, `auth/`, `settings/`.
- `lib/flavors/` — `external`/`internal` Firebase project configs, picked via
  `--dart-define=FLAVOR=`.
- `chrome_extension/` — the browser-activity companion extension (see its
  own [README](chrome_extension/README.md) for how to load it).
- Platform-abstracted services (auth, Firestore data layer, app blocking,
  usage tracking, notifications) live in the companion
  [`daily_routine_sdk`](https://github.com/kasinadhsarma/daily_routine_sdk)
  repo, pulled in as a git dependency.

## Getting started

Requires the Flutter SDK (stable channel) and a Firebase project with
Firestore + Auth enabled.

1. Copy `.env.example` to `.env` and fill in your Firebase project's values
   (Firebase console → Project settings, or run `flutterfire configure` and
   point `lib/flavors/*/firebase_options.dart` at the generated values
   instead of dotenv). Create an empty `.env.local` alongside it — it's a
   listed asset for local-only overrides and can stay empty.
2. `flutter pub get`
3. `./run.sh` (interactive flavor + device picker) or
   `flutter run --dart-define=FLAVOR=external`

Deploy Firestore security rules with:

```bash
firebase deploy --only firestore:rules
```

## Building & packaging

```bash
flutter build apk --release          # Android
./install_deb.sh                     # Linux, packages build/linux into dist/*.deb
```

## CI/CD & releases

- Every push/PR runs `flutter analyze` + tests (`.github/workflows/ci.yml`).
- Pushing a tag `vX.Y.Z` that matches `pubspec.yaml`'s `version:` builds an
  Android release APK and a Linux `.deb`, then publishes both to a
  [GitHub Release](https://github.com/kasinadhsarma/daily_routine/releases)
  with auto-generated notes (`.github/workflows/release.yml`).

To cut a release: bump `version:` in `pubspec.yaml`, merge to `main`, then

```bash
git tag v1.1.0 && git push origin v1.1.0
```

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.

## License

[MIT](LICENSE)
