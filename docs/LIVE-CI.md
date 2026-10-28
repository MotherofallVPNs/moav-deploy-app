# Live CI round

The unit and widget suite never touches a network. Everything that talks to
a real MoaV box lives in `test/live/` and is tagged `live`; those files skip
themselves unless the `MOAV_TEST_*` variables are set, which is why plain
`flutter test` (and `ci.yml`) stays green without any server.

`.github/workflows/live.yml` runs that suite against the MoaV project's CI
test server (the box `MotherofallVPNs/MoaV` uses for its own live tests).
It is wired entirely behind repository secrets and does nothing until the
maintainer populates them. Nothing about the server is committed here.

## What the live tests read

| Variable | Required | Meaning |
| --- | --- | --- |
| `MOAV_TEST_HOST` | yes | Hostname or IP of the test box. |
| `MOAV_TEST_USER` | yes | SSH user, normally `root`. |
| `MOAV_TEST_SSH_KEY` | yes | Path to the private key file (`~/` is expanded). |
| `MOAV_TEST_PORT` | no | SSH port, default `22`. |
| `MOAV_TEST_DOMAIN` | no | Domain for the install idempotence check; defaults to the host. |

`test/support/live_env.dart` is the single place these are parsed. All
three required variables must be present and non-empty, otherwise every
live test reports `MOAV_TEST_* env not set` and skips.

Locally:

```
MOAV_TEST_SSH_KEY=~/.ssh/key MOAV_TEST_HOST=your.server MOAV_TEST_USER=root \
flutter test test/live
```

## Enabling the workflow

Create these **repository secrets** (Settings, Secrets and variables,
Actions). They are the only thing the maintainer has to add; the workflow
file itself needs no edit.

| Secret | Value |
| --- | --- |
| `MOAV_TEST_HOST` | The test server's hostname or IP. |
| `MOAV_TEST_USER` | The SSH user. |
| `MOAV_TEST_SSH_KEY` | The **private key** that is authorised on the box, either the PEM text as-is or base64-encoded (`base64 -w0 key`). The workflow writes it to `RUNNER_TEMP` with mode 0600 for the job and deletes it afterwards. |
| `MOAV_TEST_PORT` | Optional. SSH port if not 22. |
| `MOAV_TEST_DOMAIN` | Optional. Domain for `live_ssh_test.dart`. |

Use a key dedicated to CI, not a personal one, so it can be revoked on the
box (`~/.ssh/authorized_keys`) without affecting anyone.

### Where the job runs

By default the job runs on `ubuntu-latest`, which means the box must accept
SSH from GitHub-hosted runner addresses. If the test server only allows SSH
from a known address, register a **self-hosted runner** on a machine that
can reach it and set the repository **variable** `MOAV_LIVE_RUNNER` to that
runner's label; the workflow's `runs-on` picks it up. A self-hosted runner
needs Flutter on its `PATH` (or let `subosito/flutter-action` install it).

### Which files run

| `suite` input | Files | Touches the box |
| --- | --- | --- |
| `read-only` (default, and the nightly schedule) | `live_operate_test.dart` | No writes: `doctor`, `status`, `user list`, the Grafana health probe. |
| `users` | plus `live_users_test.dart` | Creates one `zzmoavdeploytest<pid>` user, reads its bundle, revokes it. |
| `all` | the whole `test/live/` directory | plus `live_ssh_test.dart`: installs and removes a throwaway authorised key and re-runs the installer to prove idempotence (10+ minutes). |

The nightly schedule runs `read-only`; trigger `users` or `all` by hand
from the Actions tab. A `concurrency` group keeps two rounds from
overlapping on the same box.

### Rules that still apply

Everything in [CONTRIBUTING.md](../CONTRIBUTING.md) under "Live test
policy" holds in CI as well: additive only, throwaway `zzmoavdeploytest*`
users that are revoked in `tearDownAll` even when an assertion fails, never
start, stop or restart services, never `regenerate-users`, never commit a
real hostname, user name or bundle. The workflow never prints the host: it
reaches the test process through secrets only, and GitHub masks secret
values in logs.

## Not yet wired

- `integration_test/screenshots_test.dart` needs a booted simulator or
  emulator and is driven by `tool/screenshots.sh`; it is not part of the
  live round yet.
- The round reports pass/fail only. Capturing fresh `--json` fixtures from
  the box (`docs/MOAV-CLI-GAPS.md`) is still a manual step.
