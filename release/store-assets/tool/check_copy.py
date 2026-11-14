#!/usr/bin/env python3
"""Checks the store copy drafts against the store length limits.

    python3 release/store-assets/tool/check_copy.py           # check only
    python3 release/store-assets/tool/check_copy.py --apply   # also write fastlane/metadata

A field is a `<!-- field: <path> max=<n> -->` marker followed by a ```text
block. Paths ending in .txt are relative to fastlane/metadata/.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

COPY = Path(__file__).resolve().parent.parent / "copy"
ROOT = COPY.parent.parent.parent
METADATA = ROOT / "fastlane/metadata"

FIELD = re.compile(
    r"<!-- field: (?P<path>\S+) max=(?P<max>\d+) -->\n```text\n(?P<body>.*?)\n```",
    re.DOTALL,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="write .txt fields to fastlane/metadata")
    args = parser.parse_args()

    failed = False
    seen = 0
    for doc in sorted(COPY.glob("*.md")):
        for match in FIELD.finditer(doc.read_text(encoding="utf-8")):
            seen += 1
            path, limit, body = match["path"], int(match["max"]), match["body"]
            length = len(body)
            ok = 0 < length <= limit
            # Keywords: Apple wants commas with no spaces around them.
            if path.endswith("keywords.txt") and re.search(r"\s", body):
                ok = False
            failed = failed or not ok
            print(f"{'ok  ' if ok else 'FAIL'} {length:>4}/{limit:<4} {doc.name}: {path}")
            if args.apply and ok and path.endswith(".txt"):
                target = METADATA / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(body + "\n", encoding="utf-8")
    if seen == 0:
        print("no fields found", file=sys.stderr)
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
