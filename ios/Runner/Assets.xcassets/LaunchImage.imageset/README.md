# Launch Screen Assets

`LaunchImage*.png` are the MoaV launch lockup (mark over the "MoaV Deploy"
wordmark) at 1x/2x/3x, shown centred on the dark `#0a0a0f` background set in
`LaunchScreen.storyboard`. They mirror the Flutter `MoavLockup` widget so the
first frame lands exactly on the launch screen.

Regenerate from the repo root (also rebuilds the Android drawables):

    python3 tool/splash_assets.py

If the 1x size changes, update the `<image name="LaunchImage" ...>` entry in
`Runner/Base.lproj/LaunchScreen.storyboard` to match.
