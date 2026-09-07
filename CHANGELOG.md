## v1.2.1 — 2026-09-07

- Update CHANGELOG.md for v1.2.0 [skip ci]
- Add QR code to the 2FA setup screen

## v1.2.0 — 2026-09-07

- Auto-generate CHANGELOG.md on every release
- Backfill CHANGELOG.md from commit history, fix release notes automation
- Sign CI's automated CHANGELOG commits with a dedicated commit-signing key
- test: verify commit signature with matching email
- test: verify commit signature with corrected email/key
- test: verify commit signature with noreply email
- Fix commit-signing key ID in release workflow to match the corrected key
- Add architecture documentation covering the whole ecosystem
- Remove analysis_options.yaml, update pubspec.lock
- Show an INTERNAL banner for the internal flavor, independent of build mode
- Split internal/external into genuinely separate installable Android apps
- Add TOTP-based two-factor authentication
- Bump version to 1.2.0 for release (TOTP two-factor authentication)

# Changelog

Generated from git commit history between tags (`.github/workflows/release.yml`
runs `git log <previous-tag>..<tag>` on every tagged release and prepends the
result here) — not GitHub's PR-based release notes, since this repo pushes
directly to `main` rather than through pull requests, which left the
auto-generated notes essentially empty. Not hand-edited; if a description here
is wrong, the fix is a better commit message on the next push, not editing
this file directly.

## v1.1.9 — 2026-09-06

- Fold task-completion counts into the daily activity summary

## v1.1.8 — 2026-09-06

- Wire up Crashlytics crash reporting

## v1.1.7 — 2026-09-06

- Switch rollover/Murthy poll logging from dart:developer to debugPrint

## v1.1.6 — 2026-09-04

- Show app version under Settings > About

## v1.1.5 — 2026-09-04

- Add a downloads badge to the README
- GPG-sign release artifacts and publish checksums
- Bump version to 1.1.5 for release

## v1.1.4 — 2026-09-04

- Add daily activity rollup so the raw log never grows unbounded

## v1.1.3 — 2026-09-04

- Stop activity/Murthy providers polling forever in the background

## v1.1.2 — 2026-09-04

- Fix Dashboard/Activity exhausting Firestore's quota on Linux

## v1.1.1 — 2026-09-04

- Fix task completion not resetting daily
- Bump version to 1.1.1 for release

## v1.1.0 — 2026-09-03

- Rewrite README for actual project scope, add security policy
- Extract chrome_extension into its own public repo
- Fetch full history in release workflow to fix gh release create bug
- Add Murthy: encrypted daily progress/protocols + local voice assistant
- Add usage dashboard; fix CI-breaking analyzer warning
- Bump version to 1.1.0 for release
- Fix Android manifest merge conflict with flutter_background_service
- Remove Murthy voice assistant (Hey Murthy)
- Remove stale dist/ build artifact, gitignore the folder

## v1.0.0 — 2026-09-02

- Add Windows runner support with DPI awareness and console output
- Update Flutter plugin imports and dependencies for macOS and Dart compatibility
- Update Android configuration and enhance task scheduling features
- Update Android compileSdk version and adjust local dependency for daily_routine_sdk
- Update daily schedule tasks and enhance task tile UI for better clarity
- Refactor code structure for improved readability and maintainability
- Add SCHEDULE_EXACT_ALARM permission and enhance install_deb.sh for better package management
- Request notification permissions for accurate alarm delivery on Android 12+
- Implement activity tracking feature with Chrome extension integration and Firestore support
- Fix activity tile subtitle logic and update title display in ActivityScreen
- Add MIT License file to the repository
- Add CI and tag-triggered release workflows
- Move daily_routine_sdk dev override out of tracked pubspec.yaml
- Fetch daily_routine_sdk over SSH in CI via a read-only deploy key
- Create empty .env.local placeholder in CI so analyze doesn't fail
- Install libsecret-1-dev so the CI Linux build can compile
