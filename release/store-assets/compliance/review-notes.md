# Review notes, content rating and review risks

## App Review notes (App Store Connect, App Review Information, Notes)

Paste as is. It answers the questions a reviewer is most likely to raise
before they raise them.

```text
MoaV Deploy is a server administration tool. It connects over SSH to a Linux server that the user owns and installs, configures and monitors the open-source MoaV software on that server.

It is not a VPN client. It does not use NetworkExtension, installs no VPN configuration or profile, and never routes the device's traffic. There is no entitlements file in the app.

No account or sign-in exists. To review every screen without a server:
1. Open the app. On first launch tap "Turn on app lock" and authenticate, then "Get started" on the welcome dialog.
2. Tap "Try a demo server" on the empty server list (or "Add server", then "Try a demo server").
3. Tap "Start install". The demo runs an emulated install (about 20 seconds), then "Go to the server".
4. From there, Users, Services, Health, Analytics, Server info and Donate all work on emulated data. The demo opens no network connection.

Face ID / Touch ID is used only to unlock the app.

Disguise mode (menu, "Disguise mode") is an optional, user-enabled safety feature for people in countries where running circumvention infrastructure is dangerous. When the user turns it on, the app shows a working Notes screen and a Notes icon until the user performs a gesture and enters a passcode they chose. It is off by default, documented in the app and in the store description, and can be turned off from the same screen. Public documentation: https://github.com/MotherofallVPNs/moav-deploy-app/blob/main/docs/DISGUISE.md

The "Donate" tile on a server is not a payment: it donates the server's spare bandwidth to Psiphon Conduit and Tor Snowflake. The "Support us" sheet in the menu links to web pages in Safari where people can support the open-source project; nothing is sold or unlocked in the app.

The app is free and open source (MIT): https://github.com/MotherofallVPNs/moav-deploy-app
Privacy policy: https://moav.sh/docs/deploy/privacy/
The app collects no data; there is no backend, analytics or crash reporting.
```

Sign-in required: **No**. Leave the demo account fields empty.

Google Play has no free-text review note of this kind. The equivalent is
the App access declaration (see [privacy.md](privacy.md)).

## Content rating

### Google Play (IARC questionnaire)

Play Console, App content, Content rating.

- Email: `info@moav.sh`
- Category: **Utility, Productivity, Communication, or Other**
- Violence, sexuality, language, controlled substances, gambling, crude
  humour, fear: **No** to all
- Does the app allow users to interact or exchange content with other
  users? **No.** (The system share sheet hands a file to another app the
  user picks; the app has no chat, feed or user-to-user channel.)
- Does the app share the user's current location with other users? **No**
- Does the app allow users to purchase digital goods? **No**
- Is the app a web browser or search engine? **No.** (The in-app WebView
  only opens the user's own server dashboards through the SSH tunnel.)

Expected result: Everyone / PEGI 3 / USK 0.

### App Store (age rating)

App Store Connect, App Information, Age Rating.

- Every content frequency question: **None**
- Unrestricted web access: **No** (same reason as above)
- User-generated content, messaging or chat, advertising: **No**
- Gambling, contests, loot boxes: **No**
- Medical or wellness topics: **No**

Expected result: the lowest tier (4+).

## Review risks, most likely first

These are judgement calls on store policy, not certainties. Each has what
to do if it comes up.

### 1. Money donation links in the "Support us" sheet (both stores)

The menu's "Support us" sheet has three buttons that open the browser:
"Donate (Apple Pay / Google Pay)" (Stripe Checkout), GitHub Sponsors and
Buy Me a Coffee.

- **Apple.** A free app may collect donations outside the app through
  Safari (guideline 3.2.2), which is what the sheet does, and nothing is
  unlocked in return. Reviewers still sometimes read a "support the
  developer" button as a tip that must use in-app purchase (3.1.1).
  Separately, the label names "Google Pay" inside an iOS app, which
  guideline 2.3.10 (no references to other mobile platforms) can catch.
- **Google.** Play's Payments policy exempts donations to registered
  non-profits. MotherofallVPNs is not presented as one in the app. Open
  source apps have been pulled from Play over donation links before, and
  others carry them for years. The app has passed review on the testing
  tracks with this sheet since 0.2.14; production review can be stricter.

Options, since this release must not bump the version:

- Submit 0.2.15 as is and answer a rejection if it comes. The review note
  above already explains the sheet.
- Or cut a 0.2.16 first that hides the three money buttons on iOS (keep
  "More ways to support", which goes to moav.sh) and renames the label to
  drop the wallet names. That is a code change and a new build, so it is
  outside this PR.

### 2. "VPN" in the listing (Apple guideline 5.4)

VPN apps on the App Store must use NEVPNManager and come from an
organisation account. MoaV Deploy is not a VPN app, and the review note says
so in its first two paragraphs. If the reviewer still applies 5.4:

- Reply with the same explanation and point to the missing NetworkExtension
  entitlement.
- If that fails, switch the subtitle to `Self-host your access server` and
  screenshot 1's caption to "Run your own MoaV server" (edit
  `tool/captions.json`, rerun `tool/compose.py`).
- Confirm the developer account is enrolled as an organisation. If it is an
  individual account, 5.4 is a hard stop only if Apple classes the app as a
  VPN app.

### 3. Disguise mode (Apple 2.3.1, Play Deceptive Behaviour)

Both stores prohibit hidden features and apps that conceal what they are.
The mitigations are already in place: the feature is off by default, turned
on by the user, described in the store description, shown in a screenshot
(the menu) and explained in the review note. On iOS only the icon changes;
the name stays "MoaV Deploy". If a store still objects, the choice is
between arguing the safety case and shipping that platform without the
feature.

### 4. Reviewer cannot test without a server (Apple 2.1)

Covered by the built-in demo and the steps in the review note. Do not create
a throwaway VPS for review unless Apple asks for a real one.

### 5. Privacy policy not linked inside the app (Apple 5.1.1)

See "Gaps worth closing" in [privacy.md](privacy.md). Fix in the next build
if a reviewer raises it.

### 6. Play technical requirements

The released v0.2.15 APK targets API 36 (checked with `aapt2 dump badging`),
which meets Play's current target API rule. Still open the pre-launch
report for versionCode 18 before promoting: it is the only place Play shows
device-specific warnings such as 16 KB page-size compatibility.
