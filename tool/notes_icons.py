#!/usr/bin/env python3
"""Renders the Notes decoy launcher icons (issue #15, disguise mode).

An original, deliberately generic notes icon: a white sheet with a folded
corner and ruled lines on a warm amber square. Nothing is shared with the
MoaV mark so a disguised install carries no MoaV artwork in the launcher.

Outputs:

  assets/icon/notes-icon-1024.png                      master, full bleed
  android/app/src/main/res/mipmap-*/ic_notes.png       legacy, rounded square
  android/app/src/main/res/mipmap-*/ic_notes_round.png legacy, round
  android/app/src/main/res/drawable-*/ic_notes_foreground.png
      adaptive foreground, 108dp canvas, sheet inside the 66dp safe circle
      (the background layer is the solid colour ic_notes_background)
  ios/Runner/Assets.xcassets/NotesIcon.appiconset/     alternate app icon,
      same size list as AppIcon.appiconset, no alpha

Run from the repo root:

    python3 tool/notes_icons.py

Requires Pillow (brew install pillow / pip install pillow).
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/icon/notes-icon-1024.png"
ANDROID_RES = ROOT / "android/app/src/main/res"
IOS_APPICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IOS_NOTESICON = ROOT / "ios/Runner/Assets.xcassets/NotesIcon.appiconset"

# Keep in step with ic_notes_background in res/values/colors.xml.
AMBER_TOP = (255, 200, 61)
AMBER_BOTTOM = (242, 169, 0)
AMBER_FLAT = (245, 184, 46)
PAPER = (255, 255, 255)
FOLD = (238, 232, 214)
RULE = (214, 208, 190)
TITLE_RULE = (184, 177, 156)
SHADOW = (120, 80, 0, 70)

DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
LEGACY_DP = 48
ADAPTIVE_DP = 108


def draw_sheet(size: int, box: tuple[float, float, float, float]) -> Image.Image:
    """The note sheet alone on a transparent canvas of `size` px.

    `box` is (left, top, right, bottom) as fractions of the canvas.
    """
    scale = 8  # supersample for clean edges at small sizes
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    l, t, r, b = (v * s for v in box)
    w, h = r - l, b - t
    radius = w * 0.085
    fold = w * 0.22

    # Soft drop shadow so the sheet lifts off the amber.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (l, t + h * 0.03, r, b + h * 0.03), radius=radius, fill=SHADOW
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(w * 0.04))
    img.alpha_composite(shadow)

    d = ImageDraw.Draw(img)
    d.rounded_rectangle((l, t, r, b), radius=radius, fill=PAPER)
    # Folded top-right corner: cut the corner, draw the flap underneath it.
    d.polygon([(r - fold, t), (r, t), (r, t + fold)], fill=(0, 0, 0, 0))
    d.polygon([(r - fold, t), (r - fold, t + fold), (r, t + fold)], fill=FOLD)

    # Ruled lines: a shorter, darker title rule then three body rules.
    inset = w * 0.14
    y = t + h * 0.30
    d.rounded_rectangle(
        (l + inset, y, l + inset + w * 0.46, y + h * 0.045),
        radius=h * 0.0225,
        fill=TITLE_RULE,
    )
    for i in range(3):
        y = t + h * (0.46 + i * 0.14)
        d.rounded_rectangle(
            (l + inset, y, r - inset, y + h * 0.032),
            radius=h * 0.016,
            fill=RULE,
        )
    return img.resize((size, size), Image.LANCZOS)


def amber(size: int) -> Image.Image:
    """Vertical amber gradient square."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        f = y / max(size - 1, 1)
        px_row = tuple(
            round(AMBER_TOP[c] + (AMBER_BOTTOM[c] - AMBER_TOP[c]) * f) for c in range(3)
        )
        for x in range(size):
            px[x, y] = px_row
    return img


def full_bleed(size: int) -> Image.Image:
    base = amber(size).convert("RGBA")
    base.alpha_composite(draw_sheet(size, (0.23, 0.17, 0.77, 0.83)))
    return base


def rounded(img: Image.Image, radius_frac: float) -> Image.Image:
    mask = Image.new("L", (img.width * 4, img.height * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1), radius=mask.width * radius_frac, fill=255
    )
    out = img.copy()
    out.putalpha(mask.resize(img.size, Image.LANCZOS))
    return out


def circular(img: Image.Image) -> Image.Image:
    mask = Image.new("L", (img.width * 4, img.height * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, mask.width - 1, mask.height - 1), fill=255)
    out = img.copy()
    out.putalpha(mask.resize(img.size, Image.LANCZOS))
    return out


def write_android() -> None:
    master = full_bleed(1024)
    for density, scale in DENSITIES.items():
        legacy = round(LEGACY_DP * scale)
        mip = ANDROID_RES / f"mipmap-{density}"
        mip.mkdir(parents=True, exist_ok=True)
        base = master.resize((legacy, legacy), Image.LANCZOS)
        rounded(base, 0.18).save(mip / "ic_notes.png")
        circular(base).save(mip / "ic_notes_round.png")

        adaptive = round(ADAPTIVE_DP * scale)
        # Safe zone is the centre 66dp of 108dp; the sheet stays inside it.
        fg = draw_sheet(adaptive, (0.335, 0.30, 0.665, 0.70))
        drawable = ANDROID_RES / f"drawable-{density}"
        drawable.mkdir(parents=True, exist_ok=True)
        fg.save(drawable / "ic_notes_foreground.png")


def write_ios() -> None:
    master = full_bleed(1024).convert("RGB")
    IOS_NOTESICON.mkdir(parents=True, exist_ok=True)
    contents = json.loads((IOS_APPICON / "Contents.json").read_text())
    images = []
    for entry in contents["images"]:
        size_pt = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = round(size_pt * scale)
        name = f"Notes-{entry['size']}@{scale}x.png"
        master.resize((px, px), Image.LANCZOS).save(IOS_NOTESICON / name)
        images.append({**entry, "filename": name})
    (IOS_NOTESICON / "Contents.json").write_text(
        json.dumps({"images": images, "info": contents["info"]}, indent=2) + "\n"
    )


def main() -> None:
    MASTER.parent.mkdir(parents=True, exist_ok=True)
    full_bleed(1024).convert("RGB").save(MASTER)
    write_android()
    write_ios()
    print("wrote", MASTER.relative_to(ROOT))
    print("wrote Android mipmap/drawable ic_notes* for", ", ".join(DENSITIES))
    print("wrote", IOS_NOTESICON.relative_to(ROOT))


if __name__ == "__main__":
    main()
