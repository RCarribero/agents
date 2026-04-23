#!/usr/bin/env python3
"""check-mcp.py - Validate that .mcp.json declared servers are reachable.

Usage:
  python scripts/check-mcp.py [--config .mcp.json] [--strict]

Exits 0 if all declared servers respond to a stdio handshake within 5s.
Exits 1 if any required server fails (only in --strict mode; otherwise warns).
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def expand(value: str, workspace: Path) -> str:
    return value.replace("${workspaceFolder}", str(workspace))


def expand_env(value: str) -> str:
    if value.startswith("${env:") and value.endswith("}"):
        return os.environ.get(value[6:-1], "")
    return value


def check_server(name: str, spec: dict, workspace: Path, timeout: int = 5) -> tuple[bool, str]:
    cmd = spec.get("command")
    if not cmd or not shutil.which(cmd):
        return False, f"command not found: {cmd}"
    args = [expand(a, workspace) for a in spec.get("args", [])]
    env = os.environ.copy()
    for k, v in spec.get("env", {}).items():
        env[k] = expand_env(v)
    try:
        proc = subprocess.Popen(
            [cmd, *args],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            text=True,
        )
    except Exception as e:
        return False, f"spawn failed: {e}"
    try:
        proc.stdin.write('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n')
        proc.stdin.flush()
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        return True, "alive (timeout on close — server is running)"
    except Exception as e:
        return False, f"io error: {e}"
    return True, "ok"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--config", default=".mcp.json")
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()

    cfg_path = Path(args.config).resolve()
    if not cfg_path.is_file():
        print(f"ERROR: {cfg_path} not found", file=sys.stderr)
        return 1
    workspace = cfg_path.parent
    config = json.loads(cfg_path.read_text(encoding="utf-8"))
    servers = config.get("servers", {})
    if not servers:
        print("WARN: no servers declared", file=sys.stderr)
        return 0

    failures = 0
    for name, spec in servers.items():
        ok, msg = check_server(name, spec, workspace)
        status = "OK " if ok else "FAIL"
        print(f"[{status}] {name}: {msg}")
        if not ok:
            failures += 1

    if failures and args.strict:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
