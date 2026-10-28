# Disguise mode (Notes decoy)

Issue #15. For at-risk users the installed app should look and behave like
a harmless notes utility until the owner deliberately unlocks it. This
document is the threat model, the platform behaviour and the limitations.
Read it before changing anything under `lib/security/decoy/`,
`lib/features/notes/` or the native launcher pieces.

## What the user gets

1. **Turn on** from the home menu: Disguise mode. The user picks a
   passcode (4 to 12 digits, this phone only) and one of two secret
   gestures. There is no recovery for a forgotten passcode.
2. **Launcher identity** becomes "Notes" with an original notes icon
   (Android: name and icon; iOS: icon only, see limitations).
3. **Front screen** is a small, genuinely working notes app: write, list,
   edit, swipe to delete. Notes are stored in a plain JSON file under the
   app support directory, never in the secure store.
4. **Secret unlock**: perform the gesture on the "Notes" title, then type
   the passcode on the "Locked notes" sheet. The real app appears behind
   its normal app lock (biometric / device credential), so MoaV is still
   protected by the device lock after the secret step.
5. **Leaving the app** (background) hides the real app again. The next
   resume starts at Notes; no MoaV lock prompt can appear over the decoy.
6. **Emergency wipe** stays reachable: secret unlock, then "Emergency wipe"
   on the lock screen. A wipe removes every key and server but keeps the
   disguise config, so the icon never flips back to MoaV on its own.
7. **Turn off** from the same settings screen: the launcher goes back to
   MoaV Deploy and the passcode is forgotten. Decoy notes stay.

## Secret unlock

| Step | Default | Alternative |
| --- | --- | --- |
| Gesture | Press and hold the "Notes" title in the app bar | Tap the title five times within 600 ms of each other |
| Passcode | 4 to 12 digits chosen at setup | |
| Then | The regular MoaV app lock (biometrics / passcode) | |

The gesture is chosen per device at setup and shown on the disguise
settings screen. `DecoyGesture` in `decoy_config.dart` is the place to add
another one.

### Passcode storage and rate limit

- Stored as PBKDF2-HMAC-SHA256 (100 000 iterations, 16-byte random salt),
  base64, inside the secure store entry `moav.decoy.v1` (Android Keystore
  wrapped / iOS Keychain, no iCloud sync). The passcode itself is never
  written anywhere.
- Five free attempts, then a wait of 30 s that doubles with every further
  failure, capped at one hour. The counter and the deadline are persisted,
  so killing the app does not reset them. The sheet says "Incorrect
  passcode" or "Try again in N seconds" and nothing else.

## Platform behaviour

### Android: activity-aliases

`AndroidManifest.xml` declares two launcher entries as `activity-alias`
components. The activities themselves have no launcher intent filter.

| Alias | Target | Label / icon | Default |
| --- | --- | --- | --- |
| `.MoavLauncher` | `.MainActivity` (MoaV launch theme) | MoaV Deploy, `ic_launcher` | enabled |
| `.NotesLauncher` | `.DecoyActivity` (plain paper theme) | Notes, `ic_notes` | `android:enabled="false"` |

`DecoyChannel.kt` flips them through `PackageManager.setComponentEnabledSetting`
with `DONT_KILL_APP`: the new entry is enabled before the old one is
disabled, so there is never a moment with no launcher entry. Component
state persists across app updates and reboots; it is reset by an uninstall,
which also clears the secure store, so the two never disagree after a
reinstall. On every disguised launch the Dart side re-applies the Notes
identity (`DecoyNotifier.reconcileIdentity`), which heals a switch that was
interrupted half way. The MoaV identity is only ever restored by the
explicit "Turn off disguise" action.

`DecoyActivity` is a subclass of `MainActivity` with its own window theme
(`DecoyLaunchTheme` / `DecoyNormalTheme`): a paper-coloured window and, on
Android 12+, the Notes icon as the system splash. The MoaV launch artwork is
never drawn for a disguised launch. Flutter's `MaterialApp.title` is
"Notes" whenever disguise is on, so the recent-apps label is Notes even
while the real app is revealed.

After switching, the running task still carries the old identity in the
recent-apps list until it is finished. The settings screen offers
"Close app" (`finishAndRemoveTask`) for that.

### iOS: alternate icon only

`AppDelegate.swift` sets the alternate app icon `NotesIcon`
(`UIApplication.setAlternateIconName`). iOS does **not** allow an app to
change its display name or its launch screen at runtime, so on iOS:

- the label under the icon stays "MoaV Deploy";
- the launch screen (storyboard) still shows the MoaV lockup for a moment;
- Settings and the App Store list MoaV Deploy;
- iOS shows a system alert when the icon changes.

The settings screen and the confirmation dialog say this plainly. iOS
disguise is "a different icon plus a Notes front screen", not parity with
Android.

## What disguise cannot hide

- **Settings > Apps** (Android) and **Settings** (iOS) list the application
  label "MoaV Deploy" and the package id `org.motherofallvpns.moavdeploy`.
  The application label cannot change at runtime on either platform.
- The **store listing** the app was installed from.
- The **APK / IPA itself**: both launcher identities are predeclared and
  visible to anyone who inspects the package.
- Anyone who **knows the gesture** can reach the passcode sheet; the
  passcode and its rate limit are the actual barrier.

## Threat model notes

| Threat | Mitigation |
| --- | --- |
| Shoulder surfing | Passcode field is obscured; failures give one generic message. |
| Coercion to open the app | Opening shows Notes with real notes in it. The wipe is reachable without biometrics after the secret step. |
| Device seizure, launcher search | Android: only "Notes" is a launcher entry. iOS: icon only (see above). |
| Recent-apps preview | Task label is Notes; while the real app is revealed the inactive state paints a plain paper cover (`DecoyCover`) and the real UI is offstage. Returning from background always lands on Notes. |
| Notifications | The app sends none. |
| Accessibility | The decoy title's only semantic label is "Notes"; the real app is offstage (excluded from semantics) while covered. |
| Backups | Secure-store entries are Keystore / Keychain wrapped and useless outside the device. Decoy notes are the only plain file and contain only what the user typed into the decoy. |
| Forensic residue | The real app writes nothing new for disguise beyond `moav.decoy.v1`. Decoy notes live in `<app support>/notes.json`. |
| Wipe while disguised | `SecureCredStore.wipeAll` keeps `moav.decoy.v1`; everything else is removed and verified gone. |
| Interrupted launcher switch | Idempotent re-apply on every disguised launch; new alias enabled before the old one is disabled. |
| Offline passcode guessing | PBKDF2 100k + salt; the hash sits in the hardware-backed store. Digits-only passcodes are short, so the rate limit matters: choose a long one. |

## Files

- `lib/security/decoy/decoy_config.dart`: persisted config and gestures.
- `lib/security/decoy/decoy_pin.dart`: hashing, verification, lockout policy.
- `lib/security/decoy/decoy_identity.dart`: platform channel
  (`org.motherofallvpns.moavdeploy/decoy`).
- `lib/security/decoy/decoy_provider.dart`: enable / disable / verify.
- `lib/security/decoy/decoy_gate.dart`: Notes vs real app, lifecycle.
- `lib/features/notes/`: the decoy notes app and its file store.
- `lib/features/disguise/disguise_screen.dart`: the settings screen.
- `android/.../DecoyChannel.kt`, `DecoyActivity.kt`, `AndroidManifest.xml`.
- `ios/Runner/AppDelegate.swift`, `Assets.xcassets/NotesIcon.appiconset`.
- `tool/notes_icons.py`: regenerates every Notes icon bitmap.

## Still to do

- On-device verification of the alias swap across launchers (Pixel,
  Samsung One UI), after an app update and after a reboot.
- iOS: consider a neutral launch screen so a disguised launch never flashes
  the MoaV lockup. This changes the branded splash for everyone, so it is a
  product decision.
- Android: a one-time cosmetic effect on update from a version without the
  aliases: home-screen shortcuts that pointed at `.MainActivity` are
  replaced by the `.MoavLauncher` entry.
