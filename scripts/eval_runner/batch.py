#!/usr/bin/env python3
"""batch.py - Run scorer over every contract in a manifest, aggregate results."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", required=True, help="runs/<id>/manifest.json")
    p.add_argument("--outputs-dir", required=True, help="dir containing <eval_id>.actual.txt files")
    p.add_argument("--scored-dir", required=True)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()

    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    base = Path(args.manifest).parent
    Path(args.scored_dir).mkdir(parents=True, exist_ok=True)
    results = []
    for eval_id in manifest["evals"]:
        contract = base / f"{eval_id}.contract.json"
        actual = Path(args.outputs_dir) / f"{eval_id}.actual.txt"
        if not actual.exists():
            results.append({"eval": eval_id, "resultado": "MISSING_OUTPUT"})
            continue
        scored = Path(args.scored_dir) / f"{eval_id}.scored.json"
        cmd = [sys.executable, "scripts/eval_runner/run.py", "--contract", str(contract), "--output", str(actual), "--scored", str(scored)]
        if args.strict:
            cmd.append("--strict")
        r = subprocess.run(cmd, capture_output=True, text=True)
        try:
            results.append(json.loads(r.stdout.strip().splitlines()[-1]))
        except Exception:
            results.append({"eval": eval_id, "resultado": "ERROR", "stderr": r.stderr})

    summary = {"total": len(results), "pass": sum(1 for r in results if r.get("resultado") == "PASS"), "fail": sum(1 for r in results if r.get("resultado") == "FAIL"), "partial": sum(1 for r in results if r.get("resultado") == "PARTIAL"), "missing": sum(1 for r in results if r.get("resultado") == "MISSING_OUTPUT"), "error": sum(1 for r in results if r.get("resultado") == "ERROR"), "results": results}
    print(json.dumps(summary, indent=2))
    return 0 if summary["fail"] == 0 and summary["error"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
