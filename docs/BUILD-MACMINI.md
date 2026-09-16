# Building on the Mac Mini (hermes) — external-SSD toolchain

All heavy build tooling lives on the external SSD (`/Volumes/Beezhan`), keeping the main disk clean.

## Layout
```
/Volumes/Beezhan/dev/
  env.sh              # source this in your shell profile
  android-sdk/        # ANDROID_SDK_ROOT (platform-tools, build-tools 36, platform android-36)
  caches/pub          # PUB_CACHE
  caches/gradle       # GRADLE_USER_HOME
  caches/cocoapods    # CP_HOME_DIR
  DerivedData/        # Xcode build output (set as Xcode custom DerivedData location)
```

## Activate the environment
Add to `~/.zshrc`:
```bash
source /Volumes/Beezhan/dev/env.sh
```
`env.sh` exports `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `PUB_CACHE`, `GRADLE_USER_HOME`, `CP_HOME_DIR`, `JAVA_HOME` (Temurin/OpenJDK 21 LTS — not 26, which the Android Gradle Plugin rejects), and prepends the Android tools + JDK to `PATH`.

## Installed (done)
- **Flutter** 3.47.4 (Homebrew, `/opt/homebrew`).
- **OpenJDK 21** (`brew install openjdk@21`) — set as Flutter's JDK.
- **Android SDK** on the external SSD: cmdline-tools 12, platform-tools 37, build-tools 36.0.0, platform android-36. Licenses accepted. `flutter doctor` Android toolchain ✓.
- **CocoaPods** 1.17 (`brew install cocoapods`); cache → `CP_HOME_DIR`.
- Xcode DerivedData default pointed at `/Volumes/Beezhan/dev/DerivedData`.

## Xcode — DONE
- **Xcode 27.0** installed at `/Volumes/Beezhan/applications/Xcode.app` (external SSD) and selected (`xcode-select -p` points there).
- **iOS 27.0 Simulator runtime** downloaded (`xcodebuild -downloadPlatform iOS`, ~8 GB). Note: the runtime installs under the system `CoreSimulator` location, not the external SSD — that ~8 GB stays on the main disk (Apple doesn't support relocating it cleanly).
- `flutter doctor` → **Xcode ✓**. Verified: `flutter build ios --simulator --debug` succeeds (`build/ios/iphonesimulator/Runner.app`).

## Still needed (manual — needs your hands)
1. **Signing accounts** (only for distribution, not local testing): Apple Developer Program ($99/yr; org enrollment needs a D-U-N-S), Google Play Console ($25 one-time).

## What you can build today (no paid accounts)
- **Android APK:** `flutter build apk --release` → sideload to any device/emulator.
- **iOS Simulator:** `flutter run` on a booted simulator (once Xcode is installed).
- **Your own iPhone:** free Apple ID via Xcode (7-day profile).
TestFlight / App Store / Play Store need the paid accounts above.

## Notes
- `flutter doctor` flags "multiple adb binaries" — harmless; prefer the external SDK's `platform-tools/adb` (it's first in PATH via `env.sh`).
- Builds are heavy and share this Mac with OpenClaw; run them on-demand, not as a 24/7 runner.
