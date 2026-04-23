#!/usr/bin/env python3
"""validate-models.py - Reject agents that declare unsupported model IDs.

Reads model: from each agents/*.agent.md frontmatter and validates against
ALLOWED_MODELS. Update ALLOWED_MODELS to match the model IDs effectively
exposed by the host runtime (GitHub Copilot / runSubagent capability).

Exits 1 on any invalid id.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Conservative allow-list. Update as new models become available in the host.
ALLOWED_MODELS = {
    # Legacy/named-version aliases used in this repo's agent contracts.
    "GPT-5.4",
    "Claude Sonnet 4.6",
    "Claude Opus 4.6",
    "Claude Haiku 4.5",
    # Generic identifiers (kept for forward compatibility with runtime).
    "claude-3-5-sonnet",
    "claude-3-5-haiku",
    "claude-sonnet-4",
    "claude-opus-4",
    "claude-haiku-4",
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4.1",
    "gpt-5",
    "o1",
    "o3-mini",
}

FRONTMATTER_MODEL = re.compile(r"^model:\s*['\"]?([^'\"#\n]+?)['\"]?\s*(?:#.*)?$", re.MULTILINE)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    agents = sorted((root / "agents").glob("*.agent.md"))
    bad: list[tuple[Path, str]] = []
    for f in agents:
        text = f.read_text(encoding="utf-8")
        m = FRONTMATTER_MODEL.search(text)
        if not m:
            continue
        mid = m.group(1).strip()
        if mid not in ALLOWED_MODELS:
            bad.append((f, mid))
    if bad:
        print("ERROR: unsupported model IDs:", file=sys.stderr)
        for f, mid in bad:
            print(f"  {f.relative_to(root)}: {mid}", file=sys.stderr)
        print(f"\nAllowed: {sorted(ALLOWED_MODELS)}", file=sys.stderr)
        return 1
    print(f"OK: {len(agents)} agents validated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
