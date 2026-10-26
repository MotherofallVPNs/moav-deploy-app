# Security policy

MoaV Deploy is built for people whose safety depends on it. If you find a
weakness, please report it privately before discussing it anywhere public.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting on this repository: open the
**Security** tab and choose **Report a vulnerability**. Include the app
version, the platform, steps to reproduce, and what an attacker could gain.
Do not include real server hostnames, SSH keys or bundle links.

You will get an acknowledgement, and a fix or a mitigation plan before any
public disclosure. Please allow a reasonable window for that.

## Scope

In scope: anything in this repository, including the install job the app
writes to a server, key handling, the app lock, the emergency wipe, log
redaction, and the release pipeline.

Out of scope: the MoaV server stack itself (report that to
[MotherofallVPNs/MoaV](https://github.com/MotherofallVPNs/MoaV)), and issues
that require a compromised phone or a compromised server.

## What the app promises

- Private keys and passwords live only in the platform secure store and leave
  the device only inside the SSH handshake.
- No telemetry, no crash reporting, no backend. The app talks to your server
  and nothing else.
- Errors are scrubbed of hosts, usernames, keys and links before they reach a
  log or a notice.
- The emergency wipe removes every stored server, key and install handle.

If you believe any of these is not true in a shipped build, that is a
vulnerability. Please report it.
