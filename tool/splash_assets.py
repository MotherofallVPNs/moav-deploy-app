#!/usr/bin/env python3
"""Renders the native launch screen images from the bundled brand assets.

The launch lockup (MoaV mark over the "MoaV Deploy" wordmark) mirrors the
Flutter `MoavLockup` widget pixel for pixel: same mark size, gap, font
sizes, weights and accent gradient, so the first Flutter frame lands on top
of the native splash without anything moving.

Outputs (all transparent PNG, drawn on the #0a0a0f window background):

  android/app/src/main/res/drawable-*/splash_logo.png   lockup, 120dp mark
  android/app/src/main/res/drawable-*/splash_icon.png   Android 12+ splash
      icon: 288dp canvas, mark fitted to the 192dp safe circle
  ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage*.png
      lockup at 1x/2x/3x

Run from the repo root after changing the mark or the wordmark:

    python3 tool/splash_assets.py

Requires Pillow with FreeType (brew install pillow / pip install pillow).
"""

from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/icon/icon-foreground.png"
FONT_BOLD = ROOT / "assets/fonts/Inter-Bold.ttf"
FONT_MEDIUM = ROOT / "assets/fonts/Inter-Medium.ttf"
ANDROID_RES = ROOT / "android/app/src/main/res"
IOS_IMAGESET = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"

# Geometry in dp, kept in sync with MoavLockup in lib/theme/moav_theme.dart.
MARK_DP = 120
GAP_DP = 24
WORDMARK_SIZE = 26
WORDMARK_SPACING = -0.2  # letterSpacing applied to every glyph
SUFFIX_GAP_DP = 6
# MoavColors.cyan -> MoavColors.purple, the accent gradient (135deg).
CYAN = (0x00, 0xD4, 0xFF)
PURPLE = (0x7B, 0x5C, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF)

# Android 12+ system splash: 288dp icon, content inside a 192dp circle.
SPLASH_ICON_DP = 288
SPLASH_ICON_SAFE_DP = 192

ANDROID_DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
IOS_SCALES = {1: "LaunchImage.png", 2: "LaunchImage@2x.png", 3: "LaunchImage@3x.png"}


def font_metrics(path: Path) -> tuple[int, int, int]:
    """Returns (unitsPerEm, ascender, descender) from the hhea table.

    Flutter's text layout sizes a line from these, so the wordmark baseline
    sits exactly where the Text widget puts it.
    """
    data = path.read_bytes()
    count = struct.unpack(">H", data[4:6])[0]
    tables = {}
    for i in range(count):
        off = 12 + 16 * i
        tag = data[off : off + 4].decode("latin-1")
        tables[tag] = struct.unpack(">I", data[off + 8 : off + 12])[0]
    upm = struct.unpack(">H", data[tables["head"] + 18 : tables["head"] + 20])[0]
    asc, desc = struct.unpack(">hh", data[tables["hhea"] + 4 : tables["hhea"] + 8])
    return upm, asc, desc


def gradient_box(width: int, height: int) -> Image.Image:
    """Cyan-to-purple along the top-left -> bottom-right diagonal (Flutter's
    LinearGradient with Alignment.topLeft/bottomRight)."""
    px = bytearray()
    denom = float(width * width + height * height) or 1.0
    for y in range(height):
        for x in range(width):
            t = (x * width + y * height) / denom
            px += bytes(round(c + (p - c) * t) for c, p in zip(CYAN, PURPLE))
    return Image.frombytes("RGB", (width, height), bytes(px))


def render_lockup(scale: float) -> Image.Image:
    upm, asc, desc = font_metrics(FONT_BOLD)
    size = WORDMARK_SIZE * scale
    ascent = asc / upm * size
    line_h = (asc - desc) / upm * size
    spacing = WORDMARK_SPACING * scale

    bold = ImageFont.truetype(str(FONT_BOLD), size=size)
    medium = ImageFont.truetype(str(FONT_MEDIUM), size=size)
    w_brand = bold.getlength("MoaV") + spacing * len("MoaV")
    w_suffix = medium.getlength("Deploy") + spacing * len("Deploy")
    w_word = w_brand + SUFFIX_GAP_DP * scale + w_suffix

    mark_px = MARK_DP * scale
    canvas_w = math.ceil(max(mark_px, w_word))
    canvas_h = math.ceil(mark_px + GAP_DP * scale + line_h)
    out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))

    mark = Image.open(MASTER).convert("RGBA")
    mark = mark.resize((round(mark_px), round(mark_px)), Image.LANCZOS)
    out.alpha_composite(mark, (round((canvas_w - mark_px) / 2), 0))

    top = mark_px + GAP_DP * scale
    baseline = top + ascent
    x = (canvas_w - w_word) / 2

    # "MoaV": draw the glyphs as a mask, then pull the gradient through it.
    box_w, box_h = math.ceil(w_brand), math.ceil(line_h)
    mask = Image.new("L", (box_w, box_h), 0)
    ImageDraw.Draw(mask).text((0, ascent), "MoaV", font=bold, fill=255, anchor="ls")
    brand = gradient_box(box_w, box_h).convert("RGBA")
    brand.putalpha(mask)
    out.alpha_composite(brand, (round(x), round(top)))

    draw = ImageDraw.Draw(out)
    x_suffix = x + w_brand + SUFFIX_GAP_DP * scale
    draw.text((x_suffix, baseline), "Deploy", font=medium, fill=WHITE, anchor="ls")
    return out


def render_splash_icon(scale: float) -> Image.Image:
    canvas = round(SPLASH_ICON_DP * scale)
    inner = round(SPLASH_ICON_SAFE_DP * scale)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    mark = Image.open(MASTER).convert("RGBA").resize((inner, inner), Image.LANCZOS)
    out.alpha_composite(mark, ((canvas - inner) // 2, (canvas - inner) // 2))
    return out


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"{path.relative_to(ROOT)}  {img.width}x{img.height}")


def main() -> int:
    for density, scale in ANDROID_DENSITIES.items():
        save(render_lockup(scale), ANDROID_RES / f"drawable-{density}/splash_logo.png")
        save(render_splash_icon(scale), ANDROID_RES / f"drawable-{density}/splash_icon.png")
    for scale, name in IOS_SCALES.items():
        save(render_lockup(float(scale)), IOS_IMAGESET / name)
    one_x = render_lockup(1.0)
    print(f"LaunchScreen.storyboard image size: {one_x.width}x{one_x.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
