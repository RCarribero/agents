#!/usr/bin/env python3
"""run.py - Score one eval contract against an actual agent output.

Usage:
  python scripts/eval_runner/run.py \
      --contract runs/<id>/eval-001.contract.json \
      --output runs/<id>/eval-001.actual.txt \
      --scored runs/<id>/eval-001.scored.json

Scoring is deterministic. Each criterion is checked with a small DSL:
  - Substrings/agents found vs not-found in the actual output
  - JSON fields equal/contained/excluded

DSL is encoded inside the criterion string with marker tokens:
  AGENT_PRESENT:<name>     -> requires "<name>" to appear
  AGENT_ABSENT:<name>      -> requires "<name>" NOT to appear
  PHASE_PRESENT:<n>        -> requires "Fase <n>" or "Phase <n>"
  CONTAINS:<substring>     -> raw substring match
  REGEX:<pattern>          -> regex match (multiline, case-insensitive)

Legacy criteria (free-text, no marker) are scored INDETERMINATE and counted
toward PARTIAL unless --strict is set (then they fail).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


MARKER_RE = re.compile(r"^(AGENT_PRESENT|AGENT_ABSENT|PHASE_PRESENT|CONTAINS|REGEX):(.+)$")


def score_criterion(criterio: str, actual: str) -> tuple[bool | None, str]:
    """Return (cumplido_or_None_if_indeterminate, detail)."""
    m = MARKER_RE.match(criterio.strip())
    if not m:
        return None, "no marker — heuristic skipped"
    kind, arg = m.group(1), m.group(2).strip()
    if kind == "AGENT_PRESENT":
        ok = re.search(rf"\b{re.escape(arg)}\b", actual) is not None
        return ok, f"present={ok}"
    if kind == "AGENT_ABSENT":
        ok = re.search(rf"\b{re.escape(arg)}\b", actual) is None
        return ok, f"absent={ok}"
    if kind == "PHASE_PRESENT":
        ok = re.search(rf"\b(Fase|Phase)\s*{re.escape(arg)}\b", actual, re.I) is not None
        return ok, f"phase={ok}"
    if kind == "CONTAINS":
        ok = arg in actual
        return ok, f"contains={ok}"
    if kind == "REGEX":
        try:
            ok = re.search(arg, actual, re.I | re.M) is not None
        except re.error as e:
            return False, f"bad regex: {e}"
        return ok, f"regex={ok}"
    return None, "unknown marker"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--contract", required=True)
    p.add_argument("--output", required=True, help="Plain-text or JSON capture of agent output")
    p.add_argument("--scored", required=True)
    p.add_argument("--strict", action="store_true", help="Indeterminate criteria fail instead of being skipped")
    args = p.parse_args()

    contract = json.loads(Path(args.contract).read_text(encoding="utf-8"))
    actual = Path(args.output).read_text(encoding="utf-8")

    criteria = contract.get("scoring", {}).get("criteria", [])
    pass_count = 0
    fail_count = 0
    skip_count = 0
    for c in criteria:
        cum, detail = score_criterion(c["criterio"], actual)
        if cum is True:
            c["cumplido"] = True
            pass_count += 1
        elif cum is False:
            c["cumplido"] = False
            fail_count += 1
        else:
            if args.strict:
                c["cumplido"] = False
                fail_count += 1
            else:
                c["cumplido"] = None
                skip_count += 1
        c["detalle"] = detail

    if fail_count == 0 and skip_count == 0:
        resultado = "PASS"
    elif pass_count == 0:
        resultado = "FAIL"
    else:
        resultado = "PARTIAL"
    contract["scoring"]["resultado"] = resultado
    contract["scoring"]["counts"] = {"pass": pass_count, "fail": fail_count, "indeterminate": skip_count}

    Path(args.scored).write_text(json.dumps(contract, indent=2), encoding="utf-8")
    print(json.dumps({"eval": contract.get("eval_id"), "resultado": resultado, "counts": contract["scoring"]["counts"]}))
    return 0 if resultado == "PASS" else (1 if resultado == "FAIL" else 0)


if __name__ == "__main__":
    sys.exit(main())
