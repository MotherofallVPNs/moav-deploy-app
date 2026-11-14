# Store assets: first public release

Everything needed to fill in the App Store and Google Play listings for
MoaV Deploy 0.2.15 (build 18). Start with
[MANUAL-CHECKLIST.md](MANUAL-CHECKLIST.md): it lists each console step and
the file to take the value from.

## Contents

| Path | What |
|---|---|
| `MANUAL-CHECKLIST.md` | The by-hand steps in App Store Connect and Play Console |
| `copy/app-store.md` | Name, subtitle, promotional text, keywords, description, What's New, URLs, category |
| `copy/google-play.md` | Title, short and full description, release notes, category, contact details |
| `compliance/privacy.md` | Privacy policy URL, Play Data safety answers, App Store privacy label, with code evidence |
| `compliance/export-compliance.md` | Encryption answers, the France question, country availability |
| `compliance/review-notes.md` | App Review notes to paste, content rating answers, review risks |
| `screenshots/ios/iphone-6.9/` | 10 screenshots, 1290x2796 |
| `screenshots/ios/iphone-6.5/` | 10 screenshots, 1242x2688 |
| `screenshots/ios/ipad-12.9/` | 10 screenshots, 2048x2732 (the app ships for iPad) |
| `screenshots/android/phone/` | 8 screenshots, 1080x1920 (Play allows 8) |
| `branding/ios-app-icon-1024.png` | 1024x1024, no alpha, square corners |
| `branding/play-icon-512.png` | 512x512, 32-bit PNG |
| `branding/play-feature-graphic-1024x500.png` | Play feature graphic |
| `tool/` | Scripts that produce and check all of the above |

The screenshots show the app's built-in demo server, so every value on
screen is emulated documentation data (RFC 2606 hosts, synthetic keys). The
"Frankfurt" and "Home lab" rows in the server list are sample profiles added
by the capture run for the same reason.

## Regenerating

From the repo root. Needs Flutter, Xcode with the two simulators below, the
Android SDK with an AVD, and Python 3 with Pillow.

```
release/store-assets/tool/capture.sh iphone     # iPhone 18 Pro Max simulator
release/store-assets/tool/capture.sh ipad       # iPad Pro 13-inch (M5) simulator
release/store-assets/tool/capture.sh android    # AVD moav_api35 (1080x2400)
python3 release/store-assets/tool/compose.py    # frames, captions, icons, feature graphic
python3 release/store-assets/tool/check_copy.py # store length limits
```

- `capture.sh` boots the device if needed, sets a clean 9:41 status bar,
  runs `tool/store_shots.dart` with `flutter drive` and writes the raw
  device screenshots to `build/store-shots/<target>/` (ignored by git). It
  uninstalls the app and restores the device state when it exits. Override
  the devices with `MOAV_IPHONE_SIM`, `MOAV_IPAD_SIM`, `MOAV_ANDROID_AVD`.
- The run uses an in-memory credential store and the demo controller. It
  opens no SSH connection and writes nothing to the keychain or keystore.
- `compose.py` reads the raw shots and `tool/captions.json` and writes the
  framed images at the exact store sizes. `compose.py --check` only
  verifies sizes and colour modes of what is already there.
- `check_copy.py --apply` writes the approved en-US text into
  `fastlane/metadata/` for the existing `sync_metadata` and `sync_listing`
  lanes.

To change a caption or the order, edit `tool/captions.json` and rerun
`compose.py`. The first eight entries are the Play set; iOS takes all ten.

## Known limits

- The app UI is English only, so there is one screenshot set (en-US). Both
  stores fall back to it for other listing languages.
- On iPad the app runs its phone layout stretched to the tablet width. The
  iPad screenshots are honest about that. A tablet layout, or dropping iPad
  from the build, is a product decision outside this package.
- No Android tablet screenshots (no tablet AVD on the build machine). They
  are optional on Play.
- The device frame is a plain drawn bezel, not a vendor product image, so
  it is safe to use on both stores.
