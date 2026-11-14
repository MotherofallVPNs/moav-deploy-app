# Google Play copy (en-US)

Draft for the first production release (0.2.15, versionCode 18). Same
`field:` convention as [app-store.md](app-store.md): `tool/check_copy.py`
checks the limits and `--apply` writes the blocks into
`fastlane/metadata/android/en-US/` for `fastlane android sync_listing`.

## App name (title)

Limit 30. Unchanged.

<!-- field: android/en-US/title.txt max=30 -->
```text
MoaV Deploy
```

## Short description

Limit 80.

<!-- field: android/en-US/short_description.txt max=80 -->
```text
Deploy and manage your own MoaV VPN server over SSH, right from your phone.
```

## Full description

Limit 4000. Same text as the App Store description. Play does not render
markdown; the bullet characters and capitalised headings are plain text.

<!-- field: android/en-US/full_description.txt max=4000 -->
```text
MoaV Deploy turns a plain Linux server into your own censorship-resistant access point, and lets you run it from your phone. It installs and manages MoaV (Mother of all VPNs), a free, open-source, self-hosted stack that runs 18+ circumvention protocols side by side, so when one route is blocked another keeps people online.

You bring the server: any VPS you control. The app connects to it over SSH and does the rest. No command line needed for day-to-day work.

WHAT YOU CAN DO
• Install MoaV on a fresh server with a guided setup that shows every step, then update it from your phone.
• Add and revoke users. Share each user's connection bundle as QR codes, links or a zip file.
• Start, stop and restart individual services and protocols.
• Run health checks and read the results check by check.
• Watch CPU, memory, traffic and active users, and open your server's Grafana dashboards through the SSH connection.
• Keep several servers in one app, with on-device SSH key generation and a reusable keyring.
• Give back: donate spare bandwidth to Psiphon Conduit and Tor Snowflake, or share configs with MahsaNet.

TRY IT WITHOUT A SERVER
A built-in demo server walks you through the whole app, from install to analytics, with emulated data. Nothing is dialled and no account is needed.

BUILT FOR PEOPLE AT RISK
• App lock with your fingerprint, face or device passcode.
• SSH keys and passwords are kept in your phone's secure storage and are used only to sign in to your own servers.
• Emergency wipe removes every saved server and key.
• Optional disguise mode puts a working Notes screen in front of the app until you unlock it.
• No account, no ads, no analytics, no crash reporting, no backend. The app talks to your servers and to nothing else.

PROTOCOLS ON YOUR SERVER
VLESS Reality, XHTTP, Hysteria2, Trojan, Shadowsocks, WireGuard, AmneziaWG, TrustTunnel, Telegram MTProxy, DNS tunnels and more. What is available depends on how you set up your server and on the network your users are on.

GOOD TO KNOW
• You need your own server. MoaV Deploy does not include or sell one.
• This is a server administration app, not a VPN client. It does not create a VPN connection on your phone or route your phone's traffic. To connect, use a compatible client app with the configs your server generates.
• MoaV Deploy is free and open source (MIT licence). Source code: https://github.com/MotherofallVPNs/moav-deploy-app

Docs: https://moav.sh/docs
```

## Release notes (What's new)

Limit 500. This is a draft only and is **not** applied by
`check_copy.py --apply`: the repo's rule (`docs/RELEASING.md`) is that
`fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` is the single
source for a release, and `18.txt` already holds the notes that shipped with
the 0.2.15 testing build. When you promote versionCode 18 to production the
Play Console lets you edit the notes for the production release; paste this
there if you want first-release wording instead of the bug-fix line.

<!-- field: release-notes-draft max=500 -->
```text
First public release of MoaV Deploy.

• Install MoaV on your own server with a guided setup
• Add users and share their connection bundles as QR codes
• Control services, run health checks, view analytics and Grafana
• Built-in demo server to explore the app without a server
• App lock, emergency wipe and optional disguise mode

Thank you to everyone who tested the beta.
```

## Category and tags

- App or game: **App**
- Category: **Tools**
- Tags (Play Console, Store settings): pick from the offered list; the
  closest are "Network tools" style tags under Tools. Do not pick a VPN tag:
  the app has no `VpnService` and is not a VPN client.

## Content rating

Expected Everyone / PEGI 3. The IARC questionnaire answers are in
[review-notes.md](../compliance/review-notes.md), section Content rating.

## Contact details (Store settings)

- Email: `info@moav.sh`
- Website: `https://moav.sh`
- Phone: leave empty
- Privacy policy: `https://moav.sh/docs/deploy/privacy/`

## Other locales

`fastlane/metadata/android/` also carries ar, es-ES, fa-IR, fr-FR, ru-RU and
zh-CN. Those still hold translations of the previous description. They stay
accurate (nothing in them is wrong), they just do not mention the demo
server, disguise mode or the give-back screen. Refreshing them is a separate
translation pass and is not part of this package.
