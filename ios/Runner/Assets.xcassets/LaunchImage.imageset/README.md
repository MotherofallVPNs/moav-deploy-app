# Launch Screen Assets

`LaunchImage*.png` are the MoaV mark (the adaptive-icon foreground from
`assets/icon/icon-foreground.png`) at 1x/2x/3x, shown centred on the dark
`#0a0a0f` background set in `LaunchScreen.storyboard`. Regenerate with:

    sips -z 120 120 assets/icon/icon-foreground.png --out LaunchImage.png
    sips -z 240 240 assets/icon/icon-foreground.png --out LaunchImage@2x.png
    sips -z 360 360 assets/icon/icon-foreground.png --out LaunchImage@3x.png

You can also customise the launch screen in Xcode by opening
`Runner/Base.lproj/LaunchScreen.storyboard`.
