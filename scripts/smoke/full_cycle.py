#!/usr/bin/env python3
"""full_cycle.py - End-to-end smoke of the deterministic plane.

Simulates a full successful cycle without invoking real LLM agents:
  1. picks one harmless file
  2. computes verified_digest
  3. fabricates 3 verifier findings JSONs (all approved)
  4. writes consolidated bundle.json
  5. runs scripts/gate/gate.py with --skip-branch (no actual git ops)
  6. runs scripts/eval_runner/run.py against a synthetic contract+output
  7. asserts exit 0 from both

Exit 0 = full pipeline green.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PYTHON = sys.executable
TARGET = "stack.md"  # any tracked file


def run(cmd: list[str], cwd: Path = ROOT) -> tuple[int, str]:
    r = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def main() -> int:
    rc, digest = run([PYTHON, "scripts/verified_digest.py", "compute", "--workspace-root", str(ROOT), TARGET])
    digest = digest.strip()
    if rc != 0 or len(digest) != 64:
        print(f"FAIL: digest compute rc={rc} digest={digest!r}")
        return 1
    print(f"[1/3] digest computed: {digest[:16]}...")

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        common = {
            "task_id_base": "smoke-e2e",
            "verification_cycle": "smoke-e2e.r0",
            "branch_name": "main",
            "verified_files": [TARGET],
            "verified_digest": digest,
        }
        verdicts = {
            "auditor": {**common, "veredicto": "APROBADO", "findings": []},
            "qa": {**common, "veredicto": "CUMPLE", "test_status": "NOT_APPLICABLE", "missing_cases": []},
            "red_team": {**common, "veredicto": "RESISTENTE", "vulnerabilities": []},
        }
        bundle = {
            "task_id": "smoke-e2e",
            "verification_cycle": "smoke-e2e.r0",
            "branch_name": "main",
            "verified_files": [TARGET],
            "verified_digest": digest,
            "verdicts": verdicts,
        }
        bp = td_path / "bundle.json"
        bp.write_text(json.dumps(bundle), encoding="utf-8")

        rc, out = run([PYTHON, "scripts/gate/gate.py", "--bundle", str(bp), "--workspace-root", str(ROOT), "--skip-branch", "--skip-tools"])
        print("[2/3] gate.py output (skip-branch, skip-tools):")
        print(out)
        if rc != 0:
            print(f"FAIL: gate exit={rc}")
            return 1

        contract = {"eval_id": "smoke-e2e", "scoring": {"criteria": [{"criterio": "AGENT_PRESENT:devops"}, {"criterio": "PHASE_PRESENT:4"}]}}
        cp = td_path / "c.json"
        cp.write_text(json.dumps(contract), encoding="utf-8")
        ap = td_path / "a.txt"
        ap.write_text("Plan: tras Fase 3 verde, devops hace commit en Fase 4.", encoding="utf-8")
        sp = td_path / "s.json"
        rc, out = run([PYTHON, "scripts/eval_runner/run.py", "--contract", str(cp), "--output", str(ap), "--scored", str(sp)])
        print("[3/3] eval_runner output:")
        print(out)
        if rc != 0:
            print(f"FAIL: eval_runner exit={rc}")
            return 1

    print("\nSUCCESS: full deterministic pipeline green.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
