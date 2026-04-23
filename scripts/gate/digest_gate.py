#!/usr/bin/env python3
"""digest_gate.py - Wrap verified_digest.py with bundle-aware compare.

Usage:
  python -m scripts.gate.digest_gate --bundle bundle.json
  python -m scripts.gate.digest_gate --files a.md b.md --expected <hex>
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from verified_digest import compute_digest  # type: ignore


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", help="Path to bundle.json with verified_files + verified_digest")
    p.add_argument("--files", nargs="*", help="Explicit file list (alternative to --bundle)")
    p.add_argument("--expected", help="Expected digest (alternative to --bundle)")
    p.add_argument("--workspace-root", default=".")
    args = p.parse_args()

    if args.bundle:
        b = json.loads(Path(args.bundle).read_text(encoding="utf-8"))
        files = b["verified_files"]
        expected = b["verified_digest"]
    else:
        if not args.files or not args.expected:
            print("ERROR: provide --bundle OR (--files + --expected)", file=sys.stderr)
            return 2
        files = args.files
        expected = args.expected

    actual = compute_digest(args.workspace_root, files)
    result = {"gate": "digest", "expected": expected, "actual": actual, "ok": actual == expected}
    print(json.dumps(result))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
