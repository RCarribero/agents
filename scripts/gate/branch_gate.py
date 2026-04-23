#!/usr/bin/env python3
"""branch_gate.py - Verify branch state matches bundle.

Checks:
  1. HEAD branch == bundle.branch_name
  2. working tree clean except for bundle.verified_files
  3. local HEAD synced with remote (pull --rebase if behind, escalate on conflict)
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: str | None = None) -> tuple[int, str, str]:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", required=True)
    p.add_argument("--workspace-root", default=".")
    p.add_argument("--allow-untracked", action="store_true")
    args = p.parse_args()

    b = json.loads(Path(args.bundle).read_text(encoding="utf-8"))
    expected_branch = b["branch_name"]
    verified = set(b["verified_files"])
    cwd = args.workspace_root

    rc, head, err = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd)
    if rc != 0:
        print(json.dumps({"gate": "branch", "ok": False, "reason": f"git rev-parse failed: {err}"}))
        return 1
    if head != expected_branch:
        print(json.dumps({"gate": "branch", "ok": False, "reason": f"HEAD {head} != bundle.branch_name {expected_branch}"}))
        return 1

    rc, status, _ = run(["git", "status", "--porcelain"], cwd=cwd)
    dirty = []
    for line in status.splitlines():
        if not line.strip():
            continue
        path = line[3:].strip().replace("\\", "/")
        if path not in verified:
            dirty.append(path)
    if dirty and not args.allow_untracked:
        print(json.dumps({"gate": "branch", "ok": False, "reason": "working tree dirty outside verified_files", "dirty": dirty}))
        return 1

    rc, local_head, _ = run(["git", "log", "-1", "--format=%H"], cwd=cwd)
    rc, remote_line, _ = run(["git", "ls-remote", "origin", expected_branch], cwd=cwd)
    if remote_line:
        remote_tip = remote_line.split()[0]
        if remote_tip != local_head:
            rc, _, err = run(["git", "pull", "--rebase"], cwd=cwd)
            if rc != 0:
                print(json.dumps({"gate": "branch", "ok": False, "reason": "rebase conflict on pull", "stderr": err, "escalate": True}))
                return 2

    print(json.dumps({"gate": "branch", "ok": True, "branch": head, "synced": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
