# Security Policy

## Supported versions

This is a personal-use project. Only the latest release and `main` receive
security fixes.

## Reporting a vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Preferred: use GitHub's [private vulnerability reporting](https://github.com/kasinadhsarma/daily_routine/security/advisories/new)
("Security" tab → "Report a vulnerability") on this repo.

Alternatively, email **kasinadhsarma@gmail.com** with:

- A description of the vulnerability and its impact.
- Steps to reproduce (a minimal proof of concept, if you have one).
- Any suggested fix, if you have one.

You should get an acknowledgement within a few days. Please allow time to
investigate and ship a fix before any public disclosure.

## Scope notes

- This app reads/writes user data (routines, blocked-app selections,
  activity logs) to a Firebase project scoped per-user via
  [`firestore.rules`](firestore.rules) — `request.auth.uid == userId` on
  every collection under `users/{uid}`. Reports about rule gaps or auth
  bypasses are very welcome.
- The [Chrome extension companion](https://github.com/kasinadhsarma/daily-routine-activity-tracker)
  authenticates against a Firebase project directly from the browser
  (Firebase Auth REST + Firestore REST) — reports about its token handling
  or permission scope belong on that repo's own SECURITY.md, but are
  welcome here too if you're not sure where the boundary is.
- Firebase Web API keys embedded in this repo (`.env.example`'s shape,
  `lib/flavors/*/firebase_options.dart`) are not secrets by Firebase's own
  security model — access control is enforced by `firestore.rules`, not by
  hiding the key. Reporting a bare key as a leak isn't necessary; reporting
  a way to read/write another user's data *despite* those rules is exactly
  what this policy is for.
