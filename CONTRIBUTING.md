# Contributing

Thanks for helping with MoaV Deploy. This page covers the day-to-day rules:
branches, commits, pull requests, CI and the live test suite. Building and
signing are in [docs/BUILDING.md](docs/BUILDING.md); shipping a version is in
[docs/RELEASING.md](docs/RELEASING.md).

## Before you start

- Install Flutter 3.32 or newer (stable channel) and run `flutter doctor`.
- Run `flutter pub get`, then `flutter analyze --fatal-infos` and
  `flutter test`. Both must be clean before you open a PR.
- The app has no backend. To exercise it end to end you need a server with
  SSH access, ideally a throwaway VPS. Never point it at a server you do not
  own.

## Branches

- `main` is always releasable. CI must be green on every merge.
- Work on short-lived branches named `feat/<topic>`, `fix/<topic>`,
  `docs/<topic>` or `chore/<topic>`.
- Never push to `main` directly. Every change lands through a pull request.

## Commits

- Use conventional prefixes: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
  Scope is optional, for example `feat(users):`.
- Each commit should pass `flutter analyze --fatal-infos` and `flutter test`.
- No secrets, private hostnames, real usernames or personal data in code,
  tests, fixtures or docs. Use RFC 2606 names (`example.org`, `example.net`)
  and RFC 5737 addresses (`203.0.113.0/24`) in anything that ships.

## Pull requests

- Fill in the PR template: what changed, how you verified it (unit, widget,
  live, manual), and any CLI gaps you discovered. New gaps go into
  `docs/MOAV-CLI-GAPS.md` and a note on
  [issue #8](https://github.com/MotherofallVPNs/moav-deploy-app/issues/8).
- Before pushing, run `git fetch --prune origin` and make sure `origin/main`
  is an ancestor of your branch (`git merge-base --is-ancestor origin/main
  HEAD`). Rebase or merge if it is not.
- Keep PRs focused. A release PR only bumps the version and release notes.

## Code style

- `flutter_lints` plus `prefer_single_quotes` and `avoid_print` are enforced by
  `analysis_options.yaml`.
- Inline comments are at most two lines. Public API gets a short `///` doc
  comment when the name alone is not enough.
- Screens compose the widgets in `lib/theme/moav_theme.dart` and never reach
  into `MoavController` for styling decisions.
- User-visible strings are plain English with no em-dashes.

## CI

`.github/workflows/ci.yml` runs on every PR and on pushes to `main`:

1. `flutter pub get`
2. `flutter analyze --fatal-infos`
3. `flutter test`

Live-tagged tests are skipped automatically because the `MOAV_TEST_*`
variables are absent in CI.

## Live test policy

`test/live/` is the acceptance suite for everything that talks to a server.
It runs against whatever `MOAV_TEST_HOST` points at, which is usually a real
box with real users, so the rules are strict:

- **Additive only.** Test users are named `zzmoavdeploytest<pid>` and are
  revoked in `tearDownAll` even when an assertion fails.
- **Never** start, stop or restart services, never run `regenerate-users`,
  never modify `/opt/moav` state. Read-only commands (`doctor`, `status`,
  `user list`, `test`) are always fine.
- After a run, confirm nothing is left behind: no `zzmoavdeploytest*` under
  `outputs/bundles`, `state/users` or the `moav_state` volume.

```
MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=your.server MOAV_TEST_USER=root \
flutter test test/live
```

## Upstream coordination

Every place the app scrapes CLI text is a future bug. When the `moav` CLI
gains `--json` for a command, switch the parser in `lib/core/moav_cli.dart`
and keep the text parser as a fallback for older servers. Keep
`docs/MOAV-CLI-GAPS.md` current.

## Reporting bugs

Open an issue with the app version (the release tag or Play build), the
platform, the MoaV version on the server (`moav --version`) and the exact text
of any error notice. Do not paste SSH keys, bundle links or server hostnames.
