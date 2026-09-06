# Daily Routine — Architecture

This document explains what each piece of the Daily Routine ecosystem is,
**why** it exists in its current form (the tradeoff or incident that led to
that choice, where relevant), and what's planned next. It's written for
future-you or anyone else picking up this codebase cold.

## The ecosystem

Daily Routine isn't one repo — it's four, each with a distinct job:

| Repo | What it is | Why separate |
|---|---|---|
| [`daily_routine`](https://github.com/kasinadhsarma/daily_routine) | The Flutter app itself (Android/iOS/macOS/Windows/Linux) | — |
| [`daily_routine_sdk`](https://github.com/kasinadhsarma/daily_routine_sdk) | Shared data layer (Auth, Firestore, notifications, app-blocking) | Consumed as a git dependency so the data layer can be versioned and tested independently of the UI, and so a future second client (e.g. a web dashboard) could reuse it |
| [`daily-routine-mcp`](https://github.com/kasinadhsarma/daily-routine-mcp) | An MCP server exposing this Firestore data to Claude for analysis | Data analysis tooling has nothing to do with shipping the app — bundling it would drag Node.js/MCP dependencies into a Flutter release build for no reason |
| [`daily-routine-activity-tracker`](https://github.com/kasinadhsarma/daily-routine-activity-tracker) | A Chrome extension logging browsing activity into the same Firestore project | A Chrome extension has its own manifest/build/release lifecycle entirely unlike Flutter's; keeping it separate also means someone can install *just* the tracker without the app |

All four write to (or read from) the same Firebase project, keyed by
Firebase Auth `uid`. That's the integration point — there's no other shared
runtime between them.

## Why Flutter + Firebase at all

- **Flutter**: one codebase across Android, iOS, macOS, Windows, and Linux —
  the whole point of the app is a personal daily-routine tracker the owner
  actually uses across their own devices, so cross-platform wasn't optional.
- **Firebase (Auth + Firestore)**: managed auth and a realtime database
  without standing up and operating a backend for what is, at its core, a
  single-user personal tool. The tradeoff is the Spark (free) plan's 50k
  reads/day quota — see "Firestore quota exhaustion" below for what that
  tradeoff actually cost.

## Layer by layer

### 1. UI layer (`lib/features/*`, `daily_routine`)

Riverpod for state (`StreamProvider`, `FutureProvider`, plain `Provider`)
and `go_router` for navigation. Each feature (`auth`, `routines`,
`activity`, `dashboard`, `murthy`, `blocking`, `settings`) is a self-contained
folder with its own `screens/` and `providers/` — chosen so a feature can be
understood (or removed — see the Murthy voice assistant below) without
tracing state through the whole app.

**Why Riverpod specifically, and why `.autoDispose` matters**: providers
that aren't `.autoDispose` keep listening (and, for REST-backed services on
Linux, keep *polling*) even after the screen showing them is gone. This
wasn't theoretical — it's the root cause covered below.

### 2. Data layer (`daily_routine_sdk`)

Every Firebase-backed service (`ActivityRepositoryService`,
`RoutineRepositoryService`, `AuthService`, `BlockedAppsRepositoryService`,
`CrashReportingService`) is defined as an abstract interface with **two
implementations**, chosen by a factory at runtime:

- A native implementation (`cloud_firestore`, `firebase_auth`,
  `firebase_crashlytics`) for Android/iOS/macOS/Windows/web.
- A hand-rolled REST implementation (`lib/firestore_rest/`,
  `implementations/rest_*.dart`) for **Linux**, because `firebase_core` and
  `cloud_firestore` have no native Linux embedding.

**Why this split exists**: Linux desktop support was a real requirement
(the owner runs the app on Linux daily), but Firebase's plugins don't
support it. The REST implementations talk to the Firestore/Identity Toolkit
REST APIs directly over `package:http`, which means no gRPC/HTTP2 push
channel — so instead of Firestore's realtime listener, REST services poll
on a `Timer.periodic`.

**Why polling intervals are what they are** (30s for activity, 60s for
routines/blocked-apps): tuned up from far shorter intervals after those
shorter intervals caused real quota exhaustion (see below). Longer polling
is the direct, permanent fix, not a stopgap.

### 3. Encryption layer (Murthy)

`daily_routine`'s Murthy feature (daily protocols, daily progress/summary)
encrypts every document client-side with AES-256-CBC
(`lib/features/murthy/data/murthy_crypto_service.dart`) before it ever
reaches Firestore.

**Why**: this repository is public. Firestore data is otherwise only
gated by security rules, which protect against other *users* but not
against anyone reading the open-source code and understanding the schema —
and Murthy content (personal reflections/goals) is exactly the kind of data
that shouldn't be readable by "anyone who finds the project on GitHub,"
including the repo maintainers' future collaborators. The AES key lives in
the OS keystore (`flutter_secure_storage` → Android Keystore / Keychain /
libsecret) and never touches Firestore or logs. The direct cost of that
design: signing in on a new device starts a fresh key, so old Murthy
entries become permanently unreadable there. That's accepted as the price
of never syncing the key itself.

### 4. Activity tracking + rollover

Raw activity events (`users/{uid}/activity/*`) are logged continuously
(tab sessions from the desktop app and the Chrome extension, video
heartbeats from YouTube). A daily rollover
(`lib/features/activity/data/activity_rollover_service.dart`) runs once per
day, computing an `ActivitySummary` (total duration per app/site,
`tasksScheduled`/`tasksCompleted` for that day) and then deleting the raw
events it just summarized.

**Why rollover exists at all**: without it, the raw event collection grows
without bound forever, and — combined with the polling described above —
was one of three compounding causes of a real Firestore quota exhaustion
incident (429s, confirmed via Firebase Console screenshots). Rollover caps
the *stored* data permanently; the polling-interval fix above caps the
*read* cost per session. Both were necessary; neither alone was sufficient.

**Why task-completion counts are folded into the summary before rollover**:
`RoutineTask.completedDate` resets daily so "today's completed tasks" stays
meaningful in the UI — but that reset would silently erase the day's
completion count forever if it weren't captured into `ActivitySummary`
first. This was a reported bug (task counts appearing to vanish after
midnight) traced to exactly this: the reset was correct, but nothing was
preserving history before it happened.

### 5. Crash reporting

Firebase Crashlytics on Android/iOS/macOS (`FirebaseCrashReportingService`
in the SDK), wired through `runZonedGuarded` + `FlutterError.onError` in
`main.dart`, tagged with the signed-in `uid` via a `ref.listen` in
`app.dart`. Linux and Windows fall back to a no-op (`debugPrint`) — Firebase
has no Crashlytics SDK for either platform.

**Why not something else on Linux/Windows**: this was scoped and evaluated
(Sentry, which supports a plain HTTP DSN and would work headless) but not
built — no decision was made to proceed. If Linux crash visibility becomes
a real problem, that's the next lever, not Crashlytics (Google has no
Linux SDK at all, so there's no "just enable it" option there).

### 6. Release pipeline & integrity

Three concerns, each solved independently:

- **What changed**: `git log <prev-tag>..<tag>` (not
  `gh release create --generate-notes`, which summarizes merged PRs and
  produces an empty compare-link-only body for a repo that pushes straight
  to `main` — confirmed by inspecting all past release bodies). Written
  once into both the GitHub Release body and `CHANGELOG.md`.
- **Tamper/corruption detection**: `SHA256SUMS` generated over every
  release artifact.
- **Provenance** — proving a downloaded `.deb`/`.apk` was actually built by
  this repo's CI, not re-uploaded or substituted: every artifact and the
  checksum file are GPG-signed with a release-artifact-signing key whose
  public half is committed to the repo (`release-signing-key.asc`).
- **Commit/tag provenance** (separate key from the above, deliberately —
  see below): every commit and tag, including CI's own automated
  `CHANGELOG.md` commits, is GPG-signed and shows GitHub's "Verified"
  badge, proving *who* made each change, not just what's in the binary.

**Why two different GPG keys instead of one**: the artifact-signing key's
public half is meant for end users verifying a download; the
commit-signing key's UID is deliberately the GitHub-provided noreply email
address (not a real inbox) so it satisfies GitHub's push-privacy
protection and its "signature email must match commit email" check at the
same time — a real personal email couldn't do both without disabling email
privacy. Keeping them separate means neither concern's rotation affects
the other.

### 7. MCP server (`daily-routine-mcp`)

Exposes routine tasks, activity, and (when
`MURTHY_ENCRYPTION_KEY_BASE64` is supplied) decrypted Murthy data to Claude
via the Model Context Protocol, so questions like "how did I spend my time
yesterday" or "am I keeping up with my routines" can be answered directly
against live Firestore data instead of manually exporting it.

**Why it needs the Murthy key separately**: the whole point of client-side
encryption (layer 3) is that Firestore access alone isn't enough to read
Murthy content — so an analysis tool needs the same AES key a device would
use, exported deliberately once via the app's "Export encryption key…"
menu, never stored anywhere the app itself doesn't already trust.

### 8. Chrome extension (`daily-routine-activity-tracker`)

A Manifest V3 extension logging tab time-on-site and YouTube watch activity
into the same `users/{uid}/activity` collection the app reads via
rollover — so browser activity captured on a machine without the desktop
app installed still shows up in the same daily summaries.

**Why a `chrome.alarms` keep-alive was added**: MV3 service workers are
suspended after ~30s idle. The extension's `chrome.tabs.*` listeners are
registered top-level (the correct MV3 pattern, and Chrome is *supposed* to
wake the worker for them), but in practice tracking was observed to only
resume reliably after manually opening `chrome://extensions` → "Inspect
views: service worker." A one-minute `chrome.alarms` heartbeat nudges the
worker without relying on that manual step.

## Known limitations (not yet solved, not being actively worked)

- **No Linux/Windows crash reporting.** Scoped (Sentry), not built.
- **Signing in on a new device loses access to old Murthy entries** — an
  accepted tradeoff of never syncing the AES key, not a bug.
- **Chrome extension can't observe activity in *other* browser
  extensions.** There's no browser API for "what did extension X do" —
  only `chrome.management` for install/enable state, which isn't
  "activity" in any meaningful sense. Nothing built here without a
  concrete, scoped ask for what "integrate all chrome extensions" should
  actually mean.
- **Rollover backlog overwrite**: if rollover fails partway (e.g. security
  rules not yet deployed for `activitySummaries`/`meta`), it safely skips
  deleting the source events rather than losing data — but this means a
  backlog of un-rolled days can accumulate silently until the underlying
  cause (usually rules not deployed) is fixed.

## Next plans

Nothing here is committed — this is "the next lever to pull if the
associated problem resurfaces," not a roadmap with dates:

1. **Linux/Windows crash visibility** — likely Sentry if this becomes a
   real pain point; needs a Sentry project + DSN the owner would have to
   provision themselves.
2. **A second SDK consumer** (e.g. a web dashboard) is the actual reason
   the SDK is a separate git dependency rather than just a `lib/sdk/`
   folder inside the app — no such consumer exists yet.
3. **Downloads-badge-style visibility** was requested and shipped for the
   README; per-downloader identity was requested too and explained as
   fundamentally impossible via GitHub's release API (it exposes aggregate
   counts only, never who downloaded).
4. Revisit rollover's backlog-overwrite behavior if it causes confusion
   again — likely surfacing it in the Dashboard UI rather than only in
   logs, so a stuck rollover is visible without reading `debugPrint` output.
