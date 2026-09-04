# Daily Routine

[![CI](https://github.com/kasinadhsarma/daily_routine/actions/workflows/ci.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine/actions/workflows/ci.yml)
[![Release](https://github.com/kasinadhsarma/daily_routine/actions/workflows/release.yml/badge.svg)](https://github.com/kasinadhsarma/daily_routine/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/kasinadhsarma/daily_routine/total.svg)](https://github.com/kasinadhsarma/daily_routine/releases)

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
  - **Browser** — a companion Chrome extension,
    [`daily-routine-activity-tracker`](https://github.com/kasinadhsarma/daily-routine-activity-tracker),
    logs tab sessions and YouTube watch activity into the same Firestore
    `users/{uid}/activity` collection.
- **Auth** — email/password or Google sign-in, synced via Firebase.
- **Murthy** — daily progress, a daily summary note, and recurring daily
  protocols. Every document is encrypted client-side (AES key held in the
  OS keystore, never synced) before it reaches Firestore, so the content
  stays private even though this repo is public.
- **Dashboard** — today's task-completion progress and a breakdown of
  today's tracked app/browser activity.

## Project layout

- `lib/features/` — `routines/`, `blocking/`, `activity/`, `auth/`, `settings/`.
- `lib/flavors/` — `external`/`internal` Firebase project configs, picked via
  `--dart-define=FLAVOR=`.
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

### Verifying a release

Every release's APK, `.deb`, and `SHA256SUMS` file are GPG-signed by CI
with a dedicated release-signing key (never used for anything else, kept
only as a GitHub Actions secret). To verify a downloaded file actually
came from this repo's own release pipeline and hasn't been altered:

```bash
# one-time: import the public key
curl -fsSL https://raw.githubusercontent.com/kasinadhsarma/daily_routine/main/release-signing-key.asc | gpg --import

# per download: verify the signature
gpg --verify daily-routine-X.Y.Z_amd64.deb.asc daily-routine-X.Y.Z_amd64.deb
```

A "Good signature" from `Daily Routine Release Signing` confirms it. The
"WARNING: This key is not certified with a trusted signature" line under
that is normal and expected — it just means *you* haven't personally
marked the key as trusted in your own keyring, not that anything is
wrong with the signature itself. Key fingerprint:
`9BB5 C7AD 330C 9919 EFF1  AA6B 98FE 02C5 B7CD E4CB`.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.

## License

[MIT](LICENSE)
