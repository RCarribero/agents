#!/usr/bin/env python3
"""memoria_retrieval.py - Score memoria_global.md entries vs query, return top-N.

Replaces the prior "load full memoria_global.md into context" pattern.

Scoring: simple TF-overlap of unique tokens (lowercased, stemmed by suffix strip)
between the query and each entry. Entries are split by blank lines.

Usage:
  python scripts/memoria_retrieval.py --query "supabase auth login flutter" --top 5
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "agents" / "memoria_global.md"
WORD_RE = re.compile(r"[a-z0-9]{3,}")


def tokens(s: str) -> set[str]:
    return set(WORD_RE.findall(s.lower()))


def split_entries(text: str) -> list[str]:
    parts = re.split(r"\n\s*\n", text.strip())
    return [p.strip() for p in parts if p.strip()]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--query", required=True)
    p.add_argument("--top", type=int, default=5)
    p.add_argument("--memoria", default=str(DEFAULT_PATH))
    p.add_argument("--format", choices=["json", "text"], default="json")
    args = p.parse_args()

    mp = Path(args.memoria)
    if not mp.exists():
        print(json.dumps({"top": [], "reason": "memoria not found"}))
        return 0

    qtok = tokens(args.query)
    if not qtok:
        print(json.dumps({"top": [], "reason": "empty query"}))
        return 0

    entries = split_entries(mp.read_text(encoding="utf-8"))
    scored = []
    for e in entries:
        et = tokens(e)
        if not et:
            continue
        overlap = len(qtok & et)
        if overlap == 0:
            continue
        score = overlap / max(1, len(et)) ** 0.5
        scored.append((score, e))
    scored.sort(key=lambda x: x[0], reverse=True)
    top = [{"score": round(s, 4), "entry": e} for s, e in scored[: args.top]]

    if args.format == "text":
        for t in top:
            print(f"--- score={t['score']} ---\n{t['entry']}\n")
    else:
        print(json.dumps({"query": args.query, "top": top}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
