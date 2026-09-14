# Workflow: development, PRs, CI, releases

## Branches

- `main` is always releasable. CI must be green.
- Work happens on short-lived branches: `feat/<milestone>-<topic>`,
  `fix/<topic>`, `docs/<topic>`. Milestone work for P1 has been landing on
  `feat/scaffold-m0` via PR #9; after it merges, one branch per milestone.
- Git worktrees are used for parallel agents/humans. Never `git stash` in a
  shared worktree setup; make WIP commits instead.

## Commits

- Conventional prefixes: `feat(m3):`, `fix:`, `docs:`, `test:`, `chore:`.
- One milestone = one or a few focused commits, each passing
  `flutter analyze --fatal-infos` and `flutter test`.
- No secrets, hostnames of private boxes, or real usernames in code, tests
  or fixtures. Fixtures are sanitized (see `test/fixtures/`).

## Pull requests

- Every change goes through a PR into `main`. Link the milestone issue.
- PR description: what changed, how it was verified (unit, widget, live), and
  any CLI gaps discovered (append to `docs/MOAV-CLI-GAPS.md` and comment on
  issue #8).
- Before pushing: `git fetch --prune origin` and make sure `origin/main` is an
  ancestor of your branch (`git merge-base --is-ancestor origin/main HEAD`),
  rebasing or merging if not, so the PR merges cleanly.
- Close the milestone issue when the PR contains the finished work, with a
  one-paragraph summary of what shipped and what was verified live.

## CI (GitHub Actions, `.github/workflows/ci.yml`)

Runs on every PR and on pushes to `main`:

1. `flutter pub get`
2. `flutter analyze --fatal-infos`
3. `flutter test` (live-tagged tests are auto-skipped: no `MOAV_TEST_*` env)

Planned additions (M5): `flutter build apk --debug` smoke build, and a
nightly job that runs the live suite against `yorkschool.xyz` from a
self-hosted runner holding the test key.

## Live verification policy

The live suite (`test/live/`) is the acceptance test for every manage/monitor
milestone. Rules, because `yorkschool.xyz` is a real box with real users:

- Additive only. Test users are named `zzmoavdeploytest<pid>` and revoked in
  `tearDownAll` even when an assertion fails.
- Never start/stop/restart services, never `regenerate-users`, never touch
  `/opt/moav` state. Read-only commands (`doctor`, `status`, `user list`,
  `test`) are always fine.
- After a run, confirm no residue: no `zzmoavdeploytest*` under
  `outputs/bundles`, `state/users`, or the `moav_state` volume.

## Releases

1. Bump `version:` in `pubspec.yaml` (`X.Y.Z+N`).
2. Tag `vX.Y.Z` on `main`; write the GitHub Release from the PR summaries.
3. Build and upload: iOS via `flutter build ipa` → Transporter/App Store
   Connect (TestFlight first); Android via `flutter build appbundle` → Play
   internal track, plus `flutter build apk --split-per-abi` attached to the
   Release with SHA-256 and signature (see `docs/APP-STORES.md`).
4. Announce in the MoaV Telegram channel with the APK hash.

## Upstream coordination (MoaV CLI)

Every place the app scrapes text output is a future bug. Keep
`docs/MOAV-CLI-GAPS.md` current and mirror confirmed gaps to issue #8 so they
can be raised on `MotherofallVPNs/moav`. When the CLI gains `--json` for a
command, switch the parser in `lib/core/moav_cli.dart` and keep the text
parser as a fallback for older servers.
