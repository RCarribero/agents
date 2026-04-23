#!/usr/bin/env python3
"""tool_gate.py - Run real linters/SAST per stack and emit findings JSON.

Detects stack from stack.md and runs available tools. Missing tools = warn, not fail.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: str) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300)
        return p.returncode, (p.stdout + p.stderr).strip()
    except FileNotFoundError:
        return 127, f"not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def detect_stack(root: Path) -> set[str]:
    stack = set()
    sm = root / "stack.md"
    if sm.is_file():
        text = sm.read_text(encoding="utf-8").lower()
        for kw in ["python", "node", "typescript", "flutter", "dart", "bash", "powershell"]:
            if kw in text:
                stack.add(kw)
    if (root / "package.json").exists():
        stack.add("node")
    if (root / "pubspec.yaml").exists():
        stack.add("flutter")
    if (root / "pyproject.toml").exists() or (root / "requirements.txt").exists():
        stack.add("python")
    return stack


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--workspace-root", default=".")
    p.add_argument("--bundle", help="Optional: only lint files in bundle.verified_files")
    p.add_argument("--output", default="-")
    args = p.parse_args()

    root = Path(args.workspace_root).resolve()
    stack = detect_stack(root)
    targets: list[str] = []
    if args.bundle:
        b = json.loads(Path(args.bundle).read_text(encoding="utf-8"))
        targets = b.get("verified_files", [])

    findings: list[dict] = []
    runs: list[dict] = []

    if "python" in stack and shutil.which("ruff"):
        rc, out = run(["ruff", "check", "--output-format=json", *(targets or ["."])], str(root))
        runs.append({"tool": "ruff", "rc": rc})
        if out and out.startswith("["):
            try:
                for item in json.loads(out):
                    findings.append({"tool": "ruff", "severity": "medium", "file": item.get("filename"), "line": item.get("location", {}).get("row"), "rule": item.get("code"), "message": item.get("message")})
            except Exception:
                pass

    if "node" in stack and shutil.which("pnpm"):
        rc, out = run(["pnpm", "lint"], str(root))
        runs.append({"tool": "pnpm-lint", "rc": rc, "tail": out[-500:] if out else ""})

    if "flutter" in stack and shutil.which("flutter"):
        rc, out = run(["flutter", "analyze", "--no-fatal-infos"], str(root))
        runs.append({"tool": "flutter-analyze", "rc": rc, "tail": out[-500:] if out else ""})

    critical = [f for f in findings if f.get("severity") in ("critical", "high")]
    ok = len(critical) == 0 and all(r["rc"] in (0, 127) for r in runs)
    result = {"gate": "tool", "ok": ok, "stack": sorted(stack), "runs": runs, "findings_count": len(findings), "critical": len(critical), "findings": findings}

    payload = json.dumps(result, indent=2)
    if args.output == "-":
        print(payload)
    else:
        Path(args.output).write_text(payload, encoding="utf-8")
        print(f"wrote {args.output}")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
