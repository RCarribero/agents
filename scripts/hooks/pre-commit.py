#!/usr/bin/env python3
"""pre-commit hook — guard agents/*.agent.md, scripts/gate/, .mcp.json changes.

Refuses commit unless:
  - PR template / commit message contains `agent-change-approved: true`, OR
  - env COPILOT_AGENT_OVERRIDE=1 is set (only devops in CI uses this).

Always runs validate-models.py.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SENSITIVE = ("agents/", "scripts/gate/", ".mcp.json")


def staged_files() -> list[str]:
    r = subprocess.run(["git", "diff", "--cached", "--name-only"], capture_output=True, text=True, cwd=ROOT)
    return [l.strip().replace("\\", "/") for l in r.stdout.splitlines() if l.strip()]


def commit_message() -> str:
    p = Path(os.environ.get("GIT_COMMIT_MSG_FILE", str(ROOT / ".git" / "COMMIT_EDITMSG")))
    return p.read_text(encoding="utf-8") if p.exists() else ""


def main() -> int:
    files = staged_files()
    sensitive_hits = [f for f in files if any(f.startswith(s) for s in SENSITIVE)]

    if sensitive_hits:
        msg = commit_message()
        approved = "agent-change-approved: true" in msg
        override = os.environ.get("COPILOT_AGENT_OVERRIDE") == "1"
        if not (approved or override):
            print("BLOCKED: sensitive files staged without approval:", file=sys.stderr)
            for f in sensitive_hits:
                print(f"  - {f}", file=sys.stderr)
            print("Add `agent-change-approved: true` trailer to commit message OR set COPILOT_AGENT_OVERRIDE=1.", file=sys.stderr)
            return 1

    r = subprocess.run([sys.executable, "scripts/validate-models.py"], cwd=ROOT)
    if r.returncode != 0:
        return r.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
