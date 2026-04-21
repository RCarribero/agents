#!/usr/bin/env python3
"""
eval_baseline.py — Compare the latest aggregated eval run against the
prior baseline and emit a regression alert.

Reads all `agents/eval_outputs/eval-NNN_v*_*.json` files, groups by
(version, date) → "run key", computes per-run aggregates (total, pass,
fail, partial, score, critical_failures) and:

  - Picks the LATEST run as `current`.
  - Picks the previous run as `baseline`.
  - Reports diff. WARNING if score drops > --threshold percentage points
    or any new critical failure appears.

Usage:
  python scripts/eval_baseline.py --threshold 10 \
      --out agents/eval_outputs/baseline_diff.json

Exit codes:
  0 = no regression
  1 = regression detected (score drop > threshold or new criticals)
  2 = not enough runs to compare
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


def load_runs(outdir: Path) -> dict[tuple[str, str], list[dict]]:
    runs: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for path in sorted(outdir.glob("eval-*.json")):
        m = FNAME_RE.match(path.name)
        if not m:
            continue
        version = m.group(2)
        date = m.group(3)
        objs = _parse_concat_json(
            path.read_text(encoding="utf-8", errors="replace").strip()
        )
        if not objs:
            continue
        obj = objs[-1]
        obj["_file"] = path.name
        runs[(date, version)].append(obj)
    return runs


def aggregate(items: list[dict]) -> dict:
    total = len(items)
    p = sum(1 for x in items if x.get("resultado") == "PASS")
    f = sum(1 for x in items if x.get("resultado") == "FAIL")
    pa = sum(1 for x in items if x.get("resultado") == "PARTIAL")
    crit = [x.get("eval_id") for x in items
            if x.get("resultado") == "FAIL" and x.get("peso") == "crítico"]
    score = round(((p + 0.5 * pa) / total) * 100, 1) if total else 0.0
    return {
        "total": total,
        "pass": p,
        "fail": f,
        "partial": pa,
        "score": score,
        "critical_failures": sorted(set(crit)),
    }


def diff(current: dict, baseline: dict, threshold: float) -> dict:
    delta_score = round(current["score"] - baseline["score"], 1)
    new_criticals = sorted(
        set(current["critical_failures"]) - set(baseline["critical_failures"])
    )
    regression = (delta_score < -threshold) or bool(new_criticals)
    warnings = []
    if delta_score < -threshold:
        warnings.append(
            f"score dropped {abs(delta_score)} pts (> {threshold} threshold)"
        )
    if new_criticals:
        warnings.append(f"new critical failures: {new_criticals}")
    return {
        "current": current,
        "baseline": baseline,
        "delta_score": delta_score,
        "new_criticals": new_criticals,
        "regression": regression,
        "warnings": warnings,
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--threshold", type=float, default=10.0,
                   help="Score drop in pts that triggers regression (default 10)")
    p.add_argument("--outdir", default=str(OUTDIR))
    p.add_argument("--out", default=str(OUTDIR / "baseline_diff.json"))
    args = p.parse_args()

    outdir = Path(args.outdir)
    runs = load_runs(outdir)
    if len(runs) < 2:
        sys.stderr.write(f"need >=2 runs to compare, found {len(runs)}\n")
        return 2

    keys = sorted(runs.keys())  # (date, version) lex sort → date dominates
    cur_key, base_key = keys[-1], keys[-2]
    current = aggregate(runs[cur_key])
    baseline = aggregate(runs[base_key])
    report = {
        "current_run": {"date": cur_key[0], "version": cur_key[1]},
        "baseline_run": {"date": base_key[0], "version": base_key[1]},
        "threshold_pts": args.threshold,
        **diff(current, baseline, args.threshold),
    }
    Path(args.out).write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"baseline diff written: {args.out}")
    print(f"current  : {cur_key[1]} @ {cur_key[0]} → score {current['score']}")
    print(f"baseline : {base_key[1]} @ {base_key[0]} → score {baseline['score']}")
    print(f"delta    : {report['delta_score']} pts")
    if report["regression"]:
        print("⛔ REGRESSION:")
        for w in report["warnings"]:
            print(f"  - {w}")
        return 1
    print("✅ no regression")
    return 0


if __name__ == "__main__":
    sys.exit(main())
