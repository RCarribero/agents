#!/usr/bin/env python3
"""index_gate.py - Validate git index matches bundle.verified_files exactly.

Steps:
  1. Reset index, re-add only verified_files, then verify staged set is exactly verified_files.
  2. Compute SHA-256 over staged blobs (`git show :file`) and compare to bundle.verified_digest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: str | None = None) -> tuple[int, str, str]:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def staged_digest(files: list[str], cwd: str) -> str:
    h = hashlib.sha256()
    for rel in sorted(files):
        rc, content, err = run(["git", "show", f":{rel}"], cwd=cwd)
        if rc != 0:
            raise RuntimeError(f"git show :{rel} failed: {err}")
        key = rel.replace("\\", "/")
        h.update(key.encode())
        h.update(b"\n")
        h.update(content.encode("utf-8"))
        h.update(b"\n")
    return h.hexdigest()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", required=True)
    p.add_argument("--workspace-root", default=".")
    p.add_argument("--rebuild-index", action="store_true", help="Reset & re-add verified_files only")
    args = p.parse_args()

    b = json.loads(Path(args.bundle).read_text(encoding="utf-8"))
    verified = sorted(set(b["verified_files"]))
    expected_digest = b["verified_digest"]
    cwd = args.workspace_root

    if args.rebuild_index:
        run(["git", "reset"], cwd=cwd)
        for f in verified:
            rc, _, err = run(["git", "add", "--", f], cwd=cwd)
            if rc != 0:
                print(json.dumps({"gate": "index", "ok": False, "reason": f"git add failed: {f}: {err}"}))
                return 1

    rc, staged, _ = run(["git", "diff", "--cached", "--name-only"], cwd=cwd)
    staged_set = {l.strip().replace("\\", "/") for l in staged.splitlines() if l.strip()}
    expected_set = {f.replace("\\", "/") for f in verified}
    if staged_set != expected_set:
        extra = staged_set - expected_set
        missing = expected_set - staged_set
        print(json.dumps({"gate": "index", "ok": False, "reason": "index != verified_files", "extra": sorted(extra), "missing": sorted(missing)}))
        return 1

    try:
        actual = staged_digest(verified, cwd)
    except Exception as e:
        print(json.dumps({"gate": "index", "ok": False, "reason": str(e)}))
        return 1
    if actual != expected_digest:
        print(json.dumps({"gate": "index", "ok": False, "reason": "staged digest mismatch", "expected": expected_digest, "actual": actual}))
        return 1

    print(json.dumps({"gate": "index", "ok": True, "digest": actual}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
