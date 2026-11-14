# App Store copy (en-US)

Draft for the first public release (0.2.15). Every field below sits in a
`text` block under a `field:` marker; `tool/check_copy.py` checks the length
limits and, with `--apply`, writes the blocks into `fastlane/metadata/ios/`
so `fastlane ios sync_metadata` can push them.

App Store Connect location for each field is in
[MANUAL-CHECKLIST.md](../MANUAL-CHECKLIST.md).

## App name

Limit 30. Unchanged from TestFlight.

<!-- field: ios/en-US/name.txt max=30 -->
```text
MoaV Deploy
```

If review objects to the name, the fallback agreed in
`docs/DISTRIBUTION.md` is `Server Manager for MoaV` (23).

## Subtitle

Limit 30. Shown under the name in search results.

<!-- field: ios/en-US/subtitle.txt max=30 -->
```text
Self-hosted VPN server manager
```

Alternatives if you want "VPN" out of the subtitle (see the VPN note in
[review-notes.md](../compliance/review-notes.md)):

- `Self-host your access server` (28, the current TestFlight subtitle)
- `Deploy and manage MoaV servers` (30)

## Promotional text

Limit 170. Editable at any time without a new build.

<!-- field: ios/en-US/promotional_text.txt max=170 -->
```text
Run your own censorship-resistant VPN server. Install MoaV over SSH, add users, share QR bundles and check server health. No account, no tracking. Demo server built in.
```

## Keywords

Limit 100, comma separated, no spaces. Words already in the name or subtitle
(moav, deploy, self-hosted, vpn, server, manager) are left out on purpose:
Apple indexes those anyway.

<!-- field: ios/en-US/keywords.txt max=100 -->
```text
proxy,censorship,circumvention,vless,reality,hysteria,shadowsocks,wireguard,ssh,xray,trojan,vps
```

## Description

Limit 4000. Same text as the Google Play full description.

<!-- field: ios/en-US/description.txt max=4000 -->
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

## What's New

Limit 4000. App Store Connect does not show this field for the very first
version of an app; it applies from the first update onward. Kept here so
the text is ready and matches Google Play.

<!-- field: ios/en-US/release_notes.txt max=4000 -->
```text
First public release of MoaV Deploy.

• Install MoaV on your own server with a guided setup
• Add users and share their connection bundles as QR codes
• Control services, run health checks, view analytics and Grafana
• Built-in demo server to explore the app without a server
• App lock, emergency wipe and optional disguise mode

Thank you to everyone who tested the beta.
```

## URLs

<!-- field: ios/en-US/support_url.txt max=255 -->
```text
https://moav.sh/docs/deploy/
```

<!-- field: ios/en-US/marketing_url.txt max=255 -->
```text
https://moav.sh
```

<!-- field: ios/en-US/privacy_url.txt max=255 -->
```text
https://moav.sh/docs/deploy/privacy/
```

All three resolve (HTTP 200, checked 2026-11-14). The support URL moves
from the generic docs home to the app's own page, which is where a store
visitor should land. Support email for the review contact and Play:
`info@moav.sh` (the address in `SECURITY.md` and the privacy policy).

## Category

- Primary: **Utilities**
- Secondary: **Developer Tools**

Unchanged from `fastlane/metadata/ios/`. Not "Productivity" and not a VPN
category: the app administers a server and never tunnels the phone.

## Age rating

Expected 4+. The questionnaire answers are in
[review-notes.md](../compliance/review-notes.md), section Content rating.

## Copyright

<!-- field: ios/copyright.txt max=200 -->
```text
2026 MotherofallVPNs
```

App Store Connect adds the © sign itself. The file currently holds
`MotherofallVPNs` with no year; Apple's format is year plus rights holder.
