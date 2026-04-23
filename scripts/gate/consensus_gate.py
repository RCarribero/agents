#!/usr/bin/env python3
"""consensus_gate.py - Aggregate 3 verifier finding-files into a verdict.

Inputs: paths to auditor.json, qa.json, red_team.json (each = list of findings).
Output: consolidated decision per Fase 3 rules.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--auditor", required=True)
    p.add_argument("--qa", required=True)
    p.add_argument("--red-team", required=True)
    args = p.parse_args()

    a = load(args.auditor)
    q = load(args.qa)
    r = load(args.red_team)

    a_critical = any(f.get("severity") in ("critical", "high") for f in a.get("findings", []))
    q_failed = q.get("test_status") == "FAILED" or q.get("veredicto") == "NO CUMPLE"
    r_vuln = any(v.get("severity") in ("critical", "high") for v in r.get("vulnerabilities", []))

    veredicto = {
        "auditor": "RECHAZADO" if a_critical else "APROBADO",
        "qa": "NO CUMPLE" if q_failed else "CUMPLE",
        "red_team": "VULNERABLE" if r_vuln else "RESISTENTE",
    }
    ok = not (a_critical or q_failed or r_vuln)
    out = {"gate": "consensus", "ok": ok, "verdicts": veredicto, "summary": {
        "auditor_findings": len(a.get("findings", [])),
        "qa_test_status": q.get("test_status"),
        "red_team_vulns": len(r.get("vulnerabilities", [])),
    }}
    print(json.dumps(out, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
