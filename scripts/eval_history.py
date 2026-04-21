#!/usr/bin/env python3
"""
eval_history.py — Track eval results across runs and auto-promote
chronic PARTIAL → FAIL.

Reads all `agents/eval_outputs/eval-NNN_v*_*.json` files, groups by
eval_id, sorts by date, and applies the promotion rule:

  If the last N consecutive runs are PARTIAL with the same reason
  bucket, the latest result is promoted to FAIL in the aggregated
  history report (originals are NOT mutated — eval_runner is read-only).

Usage:
  python scripts/eval_history.py --threshold 3 --out agents/eval_outputs/history.json

Exit codes:
  0 = ok, no promotions
  1 = ok, at least one promotion (CI can decide to fail)
  2 = no inputs found
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

OUTDIR = Path("agents/eval_outputs")
FNAME_RE = re.compile(r"^eval-(\d{3})_v([^_]+)_(\d{8})\.json$")


def load_all(outdir: Path) -> dict[str, list[dict]]:
    by_id: dict[str, list[dict]] = defaultdict(list)
    for path in sorted(outdir.glob("eval-*.json")):
        m = FNAME_RE.match(path.name)
        if not m:
            continue
        eval_id = f"eval-{m.group(1)}"
        version = m.group(2)
        date = m.group(3)
        raw = path.read_text(encoding="utf-8", errors="replace").strip()
        # Files may contain multiple concatenated JSON objects — take the last one
        objs = _parse_concat_json(raw)
        if not objs:
            continue
        obj = objs[-1]
        obj["_file"] = path.name
        obj["_version"] = version
        obj["_date"] = date
        by_id[eval_id].append(obj)
    for evid in by_id:
        by_id[evid].sort(key=lambda o: (o["_date"], o["_file"]))
    return by_id


def _parse_concat_json(raw: str) -> list[dict]:
    decoder = json.JSONDecoder()
    out = []
    idx = 0
    n = len(raw)
    while idx < n:
        while idx < n and raw[idx] in " \t\r\n":
            idx += 1
        if idx >= n:
            break
        try:
            obj, end = decoder.raw_decode(raw, idx)
        except json.JSONDecodeError:
            break
        out.append(obj)
        idx = end
    return out


def reason_bucket(obj: dict) -> str:
    """Stable reason bucket from criteria detail or top-level reason."""
    if "razon" in obj:
        return str(obj["razon"])[:80]
    crits = obj.get("criterios", [])
    fails = [c for c in crits if not c.get("cumplido")]
    if fails:
        return (fails[0].get("detalle") or fails[0].get("criterio") or "unknown")[:80]
    return "no_failure_recorded"


def promote(by_id: dict[str, list[dict]], threshold: int) -> dict:
    promotions = []
    summary = []
    for evid, runs in by_id.items():
        latest = runs[-1]
        latest_result = latest.get("resultado")
        entry = {
            "eval_id": evid,
            "runs": len(runs),
            "latest_result": latest_result,
            "latest_date": latest["_date"],
            "latest_version": latest["_version"],
            "effective_result": latest_result,
            "promoted": False,
        }
        if latest_result == "PARTIAL" and len(runs) >= threshold:
            tail = runs[-threshold:]
            if all(r.get("resultado") == "PARTIAL" for r in tail):
                tail_buckets = {reason_bucket(r) for r in tail}
                if len(tail_buckets) == 1:
                    entry["effective_result"] = "FAIL"
                    entry["promoted"] = True
                    entry["promotion_reason"] = (
                        f"{threshold} consecutive PARTIAL with same bucket: "
                        f"{next(iter(tail_buckets))}"
                    )
                    promotions.append(evid)
        summary.append(entry)
    summary.sort(key=lambda e: e["eval_id"])
    return {"threshold": threshold, "promotions": promotions, "evals": summary}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--threshold", type=int, default=3,
                   help="N consecutive PARTIAL runs to promote to FAIL (default 3)")
    p.add_argument("--outdir", default=str(OUTDIR))
    p.add_argument("--out", default=str(OUTDIR / "history.json"))
    args = p.parse_args()

    outdir = Path(args.outdir)
    if not outdir.exists():
        sys.stderr.write(f"outdir not found: {outdir}\n")
        return 2

    by_id = load_all(outdir)
    if not by_id:
        sys.stderr.write("no eval outputs found\n")
        return 2

    report = promote(by_id, args.threshold)
    Path(args.out).write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"history written: {args.out}")
    print(f"evals tracked: {len(report['evals'])}")
    print(f"promotions PARTIAL→FAIL: {len(report['promotions'])}")
    for evid in report["promotions"]:
        print(f"  ⛔ {evid}")
    return 1 if report["promotions"] else 0


if __name__ == "__main__":
    sys.exit(main())
