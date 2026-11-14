"""Locates the private moav-store-assets checkout (listing images and copy)."""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
REPO = "https://github.com/MotherofallVPNs/moav-store-assets"


def assets_dir() -> Path:
    """$MOAV_STORE_ASSETS, else a moav-store-assets checkout next to this repo."""
    override = os.environ.get("MOAV_STORE_ASSETS")
    path = Path(override).expanduser() if override else ROOT.parent / "moav-store-assets"
    if not path.is_dir():
        sys.exit(
            f"store assets not found at {path}\n"
            f"clone {REPO} (private) next to this repo, or set MOAV_STORE_ASSETS"
        )
    return path.resolve()
