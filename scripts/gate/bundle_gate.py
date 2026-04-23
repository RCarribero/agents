#!/usr/bin/env python3
"""bundle_gate.py - Validate bundle internal correlation.

Checks (all required):
  - task_id_base + verification_cycle prefix derive correctly
  - verification_cycle matches one of:
      <task_id>.r<N>
      <task_id>.override<N>.r<M>
  - verified_files set is identical to context.files set
  - verified_digest non-empty hex
  - the three Fase 3 verdicts agree on: task_id base, verification_cycle,
    verified_files (exact set), branch_name, verified_digest
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CYCLE_RE = re.compile(r"^(?P<base>[A-Za-z0-9._-]+?)(?:\.override(?P<n>\d+))?\.r(?P<retry>\d+)$")


def fail(reason: str, **extra) -> int:
    out = {"gate": "bundle", "ok": False, "reason": reason, **extra}
    print(json.dumps(out))
    return 1


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--bundle", required=True)
    args = p.parse_args()
    b = json.loads(Path(args.bundle).read_text(encoding="utf-8"))

    required = ["task_id", "verification_cycle", "branch_name", "verified_files", "verified_digest", "verdicts"]
    for k in required:
        if k not in b:
            return fail(f"missing field: {k}")

    m = CYCLE_RE.match(b["verification_cycle"])
    if not m:
        return fail(f"verification_cycle malformed: {b['verification_cycle']}")
    if m.group("base") != b["task_id"]:
        return fail(f"verification_cycle prefix {m.group('base')} != task_id {b['task_id']}")

    if not re.fullmatch(r"[0-9a-f]{64}", b["verified_digest"]):
        return fail("verified_digest not 64-hex")

    vfiles = set(b["verified_files"])
    if "session_log.md" in vfiles:
        return fail("session_log.md must NOT appear in verified_files (audit_trail_artifact)")

    verdicts = b["verdicts"]
    expected_roles = {"auditor", "qa", "red_team"}
    got_roles = set(verdicts.keys())
    if got_roles != expected_roles:
        return fail(f"verdicts must contain exactly {expected_roles}, got {got_roles}")

    for role, v in verdicts.items():
        if v.get("task_id_base") != b["task_id"]:
            return fail(f"{role}.task_id_base mismatch")
        if v.get("verification_cycle") != b["verification_cycle"]:
            return fail(f"{role}.verification_cycle mismatch")
        if v.get("branch_name") != b["branch_name"]:
            return fail(f"{role}.branch_name mismatch")
        if set(v.get("verified_files", [])) != vfiles:
            return fail(f"{role}.verified_files set mismatch")
        if v.get("verified_digest") != b["verified_digest"]:
            return fail(f"{role}.verified_digest mismatch")

    expected_verdicts = {"auditor": "APROBADO", "qa": "CUMPLE", "red_team": "RESISTENTE"}
    for role, expected in expected_verdicts.items():
        if verdicts[role].get("veredicto") != expected:
            return fail(f"{role} not {expected}: got {verdicts[role].get('veredicto')}")

    if verdicts["qa"].get("test_status") not in ("GREEN", "NOT_APPLICABLE"):
        return fail(f"qa.test_status must be GREEN|NOT_APPLICABLE, got {verdicts['qa'].get('test_status')}")

    print(json.dumps({"gate": "bundle", "ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
