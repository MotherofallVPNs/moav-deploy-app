#!/usr/bin/env python3
"""Builds the store listing images from the raw captures and brand assets.

    python3 release/store-assets/tool/compose.py            # everything
    python3 release/store-assets/tool/compose.py --check    # verify outputs only

Raw captures come from capture.sh (build/store-shots/<target>/). Captions
live in captions.json next to this file. Requires Pillow with FreeType.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

TOOL = Path(__file__).resolve().parent
OUT = TOOL.parent
ROOT = OUT.parent.parent
RAW = ROOT / "build/store-shots"
FONT_BOLD = ROOT / "assets/fonts/Inter-Bold.ttf"
FONT_MEDIUM = ROOT / "assets/fonts/Inter-Medium.ttf"
ICON = ROOT / "assets/icon/icon-1024.png"
ICON_BACKGROUND = ROOT / "assets/icon/icon-background.png"
MARK = ROOT / "assets/brand/moav-mark.png"

# MoavColors in lib/theme/moav_theme.dart.
BG = (0x0A, 0x0A, 0x0F)
GLOW_TOP = (0x1A, 0x1A, 0x2E)
CYAN = (0x00, 0xD4, 0xFF)
PURPLE = (0x7B, 0x5C, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF)
TEXT_SECONDARY = (0xA0, 0xA0, 0xB0)
BEZEL = (0x1B, 0x1B, 0x27)
BEZEL_EDGE = (0x3A, 0x3A, 0x4C)

# name: (raw target, canvas size, output dir, tablet, max shots or None)
SETS = {
    "iphone-6.9": ("iphone", (1290, 2796), "screenshots/ios/iphone-6.9", False, 10),
    "iphone-6.5": ("iphone", (1242, 2688), "screenshots/ios/iphone-6.5", False, 10),
    "ipad-12.9": ("ipad", (2048, 2732), "screenshots/ios/ipad-12.9", True, 10),
    "android-phone": ("android", (1080, 1920), "screenshots/android/phone", False, 8),
}

BRANDING = {
    "branding/ios-app-icon-1024.png": ((1024, 1024), "RGB"),
    "branding/play-icon-512.png": ((512, 512), "RGBA"),
    "branding/play-feature-graphic-1024x500.png": ((1024, 500), "RGB"),
}


def font(path: Path, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), max(1, round(size)))


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    """Antialiased rounded-rectangle mask (drawn at 4x, scaled down)."""
    w, h = size
    big = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * 4 - 1, h * 4 - 1), radius=radius * 4, fill=255
    )
    return big.resize((w, h), Image.LANCZOS)


def gradient(size: tuple[int, int]) -> Image.Image:
    """The cyan to purple accent gradient, left to right."""
    w, h = size
    strip = Image.new("RGB", (256, 1))
    for x in range(256):
        t = x / 255
        strip.putpixel((x, 0), tuple(round(a + (b - a) * t) for a, b in zip(CYAN, PURPLE)))
    return strip.resize((w, h), Image.BILINEAR)


def backdrop(size: tuple[int, int]) -> Image.Image:
    """Dark canvas with a soft top glow and two accent blobs, like the app."""
    w, h = size
    sw, sh = max(1, w // 8), max(1, h // 8)
    small = Image.new("RGB", (sw, sh), BG)
    draw = ImageDraw.Draw(small)
    draw.ellipse((-sw * 0.3, -sh * 0.28, sw * 1.3, sh * 0.34), fill=GLOW_TOP)
    blobs = Image.new("RGB", (sw, sh), (0, 0, 0))
    bdraw = ImageDraw.Draw(blobs)
    bdraw.ellipse((-sw * 0.35, sh * 0.42, sw * 0.5, sh * 0.9), fill=(0, 46, 60))
    bdraw.ellipse((sw * 0.5, sh * 0.25, sw * 1.35, sh * 0.75), fill=(36, 24, 84))
    small = small.filter(ImageFilter.GaussianBlur(sw * 0.16))
    blobs = blobs.filter(ImageFilter.GaussianBlur(sw * 0.22))
    return ImageChops.add(small, blobs).resize((w, h), Image.BICUBIC)


def fit_font(path: Path, text: str, size: float, max_width: float) -> ImageFont.FreeTypeFont:
    f = font(path, size)
    while f.getlength(text) > max_width and size > 8:
        size *= 0.96
        f = font(path, size)
    return f


def device(shot: Image.Image, height: int, tablet: bool) -> Image.Image:
    """A plain rounded device around the screenshot, RGBA, [height] tall."""
    sw, sh = shot.size
    bezel = round(height * (0.011 if tablet else 0.0075))
    screen_h = height - 2 * bezel
    screen_w = round(screen_h * sw / sh)
    width = screen_w + 2 * bezel
    outer_r = width * (0.045 if tablet else 0.115)
    body = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    body.paste(Image.new("RGB", (width, height), BEZEL_EDGE), (0, 0), rounded_mask((width, height), outer_r))
    edge = max(2, round(width * 0.003))
    inner = (width - 2 * edge, height - 2 * edge)
    body.paste(Image.new("RGB", inner, BEZEL), (edge, edge), rounded_mask(inner, outer_r - edge))
    screen = shot.convert("RGB").resize((screen_w, screen_h), Image.LANCZOS)
    body.paste(screen, (bezel, bezel), rounded_mask((screen_w, screen_h), outer_r - bezel))
    return body


def glow_under(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    """Soft accent halo behind the device at [box]."""
    w, h = canvas.size
    x0, y0, x1, y1 = box
    scale = 8
    halo = Image.new("RGB", (w // scale, h // scale), (0, 0, 0))
    grad = gradient(((x1 - x0) // scale, (y1 - y0) // scale))
    grad = Image.eval(grad, lambda v: v * 30 // 100)
    halo.paste(grad, (x0 // scale, y0 // scale))
    halo = halo.filter(ImageFilter.GaussianBlur(w / scale * 0.06)).resize((w, h), Image.BICUBIC)
    canvas.paste(ImageChops.add(canvas, halo))


def framed(shot: Image.Image, size: tuple[int, int], title: str, subtitle: str, tablet: bool) -> Image.Image:
    w, h = size
    canvas = backdrop(size)
    draw = ImageDraw.Draw(canvas)
    unit = h if tablet else w * 2  # keeps type proportional on wide canvases
    title_size, sub_size = unit * 0.0375, unit * 0.0185
    title_font = fit_font(FONT_BOLD, title, title_size, w * 0.9)
    sub_font = fit_font(FONT_MEDIUM, subtitle, sub_size, w * 0.9)
    # Baselines and the device top come from the nominal sizes, not the
    # fitted ones, so every image in a set lines up.
    title_base = round(h * 0.05 + title_size)
    sub_base = round(title_base + sub_size * 1.9)
    draw.text((w / 2, title_base), title, font=title_font, fill=WHITE, anchor="ms")
    draw.text((w / 2, sub_base), subtitle, font=sub_font, fill=TEXT_SECONDARY, anchor="ms")
    device_top = sub_base + round(h * 0.04)
    device_h = h - device_top - round(h * 0.036)
    dev = device(shot, device_h, tablet)
    if dev.width > w * 0.92:
        dev = device(shot, round(device_h * w * 0.92 / dev.width), tablet)
    x = (w - dev.width) // 2
    y = device_top + (device_h - dev.height) // 2
    glow_under(canvas, (x, y, x + dev.width, y + dev.height))
    canvas.paste(dev, (x, y), dev)
    return canvas


def wordmark(height: int) -> Image.Image:
    """'MoaV Deploy' lockup text: MoaV in the accent gradient, Deploy white."""
    f = font(FONT_BOLD, height)
    moav_w = round(f.getlength("MoaV"))
    gap = round(height * 0.24)
    deploy_w = round(f.getlength("Deploy"))
    line_h = round(height * 1.25)
    img = Image.new("RGBA", (moav_w + gap + deploy_w, line_h), (0, 0, 0, 0))
    mask = Image.new("L", (moav_w, line_h), 0)
    ImageDraw.Draw(mask).text((0, 0), "MoaV", font=f, fill=255)
    img.paste(gradient((moav_w, line_h)), (0, 0), mask)
    ImageDraw.Draw(img).text((moav_w + gap, 0), "Deploy", font=f, fill=WHITE)
    return img


def feature_graphic(hub: Image.Image) -> Image.Image:
    w, h = 1024, 500
    canvas = Image.open(ICON_BACKGROUND).convert("RGB")
    # Centre crop of the square starfield to the banner ratio, then dimmed.
    crop_h = round(canvas.width * h / w)
    y0 = (canvas.height - crop_h) // 2
    canvas = canvas.crop((0, y0, canvas.width, y0 + crop_h)).resize((w, h), Image.LANCZOS)
    canvas = Image.blend(canvas, Image.new("RGB", (w, h), BG), 0.35)
    mark = Image.open(MARK).convert("RGBA").resize((150, 150), Image.LANCZOS)
    canvas.paste(mark, (56, 66), mark)
    mark_text = wordmark(64)
    canvas.paste(mark_text, (64, 232), mark_text)
    draw = ImageDraw.Draw(canvas)
    draw.text((66, 326), "Deploy and manage your own", font=font(FONT_MEDIUM, 30), fill=WHITE)
    draw.text((66, 366), "VPN server, from your phone", font=font(FONT_MEDIUM, 30), fill=WHITE)
    # The hub screenshot on a device, bleeding off the bottom edge.
    dev = device(hub, 760, tablet=False)
    x, y = w - dev.width - 96, 52
    glow_under(canvas, (x, y, x + dev.width, h))
    canvas.paste(dev, (x, y), dev)
    return canvas


def build_branding() -> None:
    (OUT / "branding").mkdir(parents=True, exist_ok=True)
    icon = Image.open(ICON)
    # App Store: 1024 px, opaque, square corners (the store applies the mask).
    icon.convert("RGB").save(OUT / "branding/ios-app-icon-1024.png", optimize=True)
    # Google Play: 512 px, 32-bit PNG.
    icon.convert("RGBA").resize((512, 512), Image.LANCZOS).save(
        OUT / "branding/play-icon-512.png", optimize=True
    )
    hub = Image.open(RAW / "android/06-server-hub.png")
    feature_graphic(hub).save(OUT / "branding/play-feature-graphic-1024x500.png", optimize=True)


def build_screenshots(captions: list[dict]) -> None:
    for raw_target, size, out_dir, tablet, limit in SETS.values():
        dest = OUT / out_dir
        dest.mkdir(parents=True, exist_ok=True)
        for old in dest.glob("*.png"):
            old.unlink()
        for index, item in enumerate(captions[:limit], start=1):
            shot = Image.open(RAW / raw_target / f"{item['shot']}.png")
            image = framed(shot, size, item["title"], item["subtitle"], tablet)
            # Stores reject alpha; save flat RGB.
            image.convert("RGB").save(dest / f"{index:02d}-{item['slug']}.png", optimize=True)


def check(captions: list[dict]) -> list[str]:
    problems = []

    def verify(path: Path, size: tuple[int, int], mode: str) -> None:
        if not path.is_file():
            problems.append(f"missing {path.relative_to(OUT)}")
            return
        with Image.open(path) as im:
            if im.size != size or im.mode != mode:
                problems.append(
                    f"{path.relative_to(OUT)}: {im.size} {im.mode}, want {size} {mode}"
                )

    for rel, (size, mode) in BRANDING.items():
        verify(OUT / rel, size, mode)
    for _, size, out_dir, _, limit in SETS.values():
        files = sorted((OUT / out_dir).glob("*.png"))
        want = min(limit, len(captions))
        if len(files) != want:
            problems.append(f"{out_dir}: {len(files)} files, want {want}")
        for path in files:
            verify(path, size, "RGB")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify existing outputs only")
    args = parser.parse_args()
    captions = json.loads((TOOL / "captions.json").read_text())["en-US"]
    if not args.check:
        build_branding()
        build_screenshots(captions)
    problems = check(captions)
    for line in problems:
        print(f"FAIL {line}", file=sys.stderr)
    if not problems:
        print("store images OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
