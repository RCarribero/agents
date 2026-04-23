#!/usr/bin/env python3
"""gate.py - Orchestrate all deterministic gates in order.

Runs (in order, short-circuit on first failure):
  1. bundle_gate    - structural bundle correlation
  2. digest_gate    - working-tree digest matches bundle
  3. branch_gate    - HEAD/clean/synced
  4. index_gate     - git index payload binding
  5. tool_gate      - real linters (warn-only by default)

Exit 0 = all gates pass -> safe to commit.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

GATE_DIR = Path(__file__).resolve().parent
PYTHON = sys.executable


def call(name: str, args: list[str]) -> tuple[int, dict]:
    cmd = [PYTHON, str(GATE_DIR / f"{name}_gate.py"), *args]
    p = subprocess.run(cmd, capture_output=True, text=True)
    body: dict
    try:
        body = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {"raw": p.stdout, "stderr": p.stderr}
    except Exception:
        body = {"raw": p.stdout, "stderr": p.stderr}
    return p.returncode, body


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", required=True)
    p.add_argument("--workspace-root", default=".")
    p.add_argument("--rebuild-index", action="store_true")
    p.add_argument("--skip-tools", action="store_true")
    p.add_argument("--skip-branch", action="store_true", help="Useful in CI where branch state is N/A")
    args = p.parse_args()

    results: dict[str, dict] = {}
    rc, results["bundle"] = call("bundle", ["--bundle", args.bundle])
    if rc != 0:
        print(json.dumps({"gate": "ALL", "ok": False, "stage": "bundle", "results": results}, indent=2))
        return 1

    rc, results["digest"] = call("digest", ["--bundle", args.bundle, "--workspace-root", args.workspace_root])
    if rc != 0:
        print(json.dumps({"gate": "ALL", "ok": False, "stage": "digest", "results": results}, indent=2))
        return 1

    if not args.skip_branch:
        rc, results["branch"] = call("branch", ["--bundle", args.bundle, "--workspace-root", args.workspace_root])
        if rc != 0:
            print(json.dumps({"gate": "ALL", "ok": False, "stage": "branch", "results": results}, indent=2))
            return 1

        index_args = ["--bundle", args.bundle, "--workspace-root", args.workspace_root]
        if args.rebuild_index:
            index_args.append("--rebuild-index")
        rc, results["index"] = call("index", index_args)
        if rc != 0:
            print(json.dumps({"gate": "ALL", "ok": False, "stage": "index", "results": results}, indent=2))
            return 1

    if not args.skip_tools:
        rc, results["tool"] = call("tool", ["--bundle", args.bundle, "--workspace-root", args.workspace_root])

    print(json.dumps({"gate": "ALL", "ok": True, "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
