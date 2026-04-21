#!/usr/bin/env python3
"""
eval_runner_harness.py — Generate runnable input contracts for each eval.

The eval system relies on LLM-driven sub-agents that this script cannot
invoke directly. What it CAN do is produce, for each requested eval, the
exact JSON contract that should be fed to the target agent, plus a
scoring stub the human/orchestrator can fill back in. Output is written
to `runs/<run_id>/eval-NNN.contract.json` so a downstream runner (manual
or LLM-driven) can pick them up deterministically.

Usage:
  python scripts/eval_runner_harness.py --version main-20260421 \
      --evals eval-001 eval-005 --out-dir runs/

  python scripts/eval_runner_harness.py --version main-20260421 \
      --diff-from-stdin   # reads `git diff --name-only` and routes via eval_diff
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

CATALOG = Path("agents/evals/eval_catalog.md")
EVAL_HEADER_RE = re.compile(r"^### (eval-\d{3})\s+—\s+(.+)$")
INPUT_BLOCK_RE = re.compile(
    r"\*\*Input:\*\*\s*\n```(?:json|dart|sql|xml)?\s*\n(.*?)\n```", re.DOTALL
)
EXPECTED_BLOCK_RE = re.compile(
    r"\*\*Expected:\*\*\s*\n```(?:json|xml)?\s*\n(.*?)\n```", re.DOTALL
)
CRITERIA_BLOCK_RE = re.compile(
    r"\*\*Criterios de éxito:\*\*\s*\n((?:- .+\n?)+)", re.MULTILINE
)
WEIGHT_RE = re.compile(r"\*\*Peso:\*\*\s*(\w+)")
TYPE_RE = re.compile(r"\*\*Tipo:\*\*\s*([\w_]+)")
GROUP_RE = re.compile(r"^## Grupo \d+ — (\w+)", re.MULTILINE)
MAPPING_ROW_RE = re.compile(
    r"^\|\s*(eval-\d{3})\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$"
)


def parse_catalog(catalog: Path) -> dict[str, dict]:
    text = catalog.read_text(encoding="utf-8")
    # Build group lookup from mapping table
    mapping: dict[str, dict] = {}
    in_table = False
    for line in text.splitlines():
        if line.strip().startswith("| Eval "):
            in_table = True
            continue
        if in_table:
            if not line.strip().startswith("|"):
                in_table = False
                continue
            if line.strip().startswith("|---"):
                continue
            m = MAPPING_ROW_RE.match(line)
            if m:
                mapping[m.group(1)] = {
                    "agents": [a.strip() for a in m.group(2).split(",")],
                    "group": m.group(3).strip(),
                }

    # Split by '### eval-NNN' headings
    sections = re.split(r"(?=^### eval-\d{3} — )", text, flags=re.MULTILINE)
    evals: dict[str, dict] = {}
    for sec in sections:
        m = EVAL_HEADER_RE.match(sec.splitlines()[0]) if sec.strip() else None
        if not m:
            continue
        eval_id, name = m.group(1), m.group(2).strip()
        in_block = INPUT_BLOCK_RE.search(sec)
        ex_block = EXPECTED_BLOCK_RE.search(sec)
        cr_block = CRITERIA_BLOCK_RE.search(sec)
        wt = WEIGHT_RE.search(sec)
        tp = TYPE_RE.search(sec)
        criteria = []
        if cr_block:
            for line in cr_block.group(1).splitlines():
                line = line.strip()
                if line.startswith("- "):
                    criteria.append(line[2:].strip())
        meta = mapping.get(eval_id, {"agents": [], "group": "unknown"})
        evals[eval_id] = {
            "eval_id": eval_id,
            "name": name,
            "type": tp.group(1) if tp else None,
            "weight": wt.group(1) if wt else None,
            "input_raw": (in_block.group(1).strip() if in_block else None),
            "expected_raw": (ex_block.group(1).strip() if ex_block else None),
            "criteria": criteria,
            "covers_agents": meta["agents"],
            "group": meta["group"],
        }
    return evals


def emit_contract(ev: dict, version: str) -> dict:
    return {
        "schema_version": "1.0",
        "eval_id": ev["eval_id"],
        "name": ev["name"],
        "type": ev["type"],
        "group": ev["group"],
        "weight": ev["weight"],
        "covers_agents": ev["covers_agents"],
        "system_version": version,
        "issued_at": dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "agent_input": ev["input_raw"],
        "agent_expected": ev["expected_raw"],
        "scoring": {
            "criteria": [
                {"criterio": c, "cumplido": None, "detalle": None}
                for c in ev["criteria"]
            ],
            "resultado": None,
            "tiempo_ejecucion_ms": None,
        },
        "instructions": (
            "Feed `agent_input` to one of `covers_agents`, capture its "
            "<director_report>, fill `scoring.criteria[*].cumplido` and "
            "`scoring.resultado` (PASS|FAIL|PARTIAL). Save back as "
            "agents/eval_outputs/<eval_id>_v<version>_<YYYYMMDD>.json."
        ),
    }


def stdin_files_to_evals(diff_script: Path) -> list[str]:
    files = [line.strip() for line in sys.stdin if line.strip()]
    if not files:
        return []
    proc = subprocess.run(
        [sys.executable, str(diff_script), "--files", *files, "--allow-empty"],
        capture_output=True, text=True, check=False,
    )
    if proc.returncode not in (0,):
        sys.stderr.write(proc.stderr)
        return []
    data = json.loads(proc.stdout)
    return data.get("evals_to_run", [])


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True, help="System version label")
    p.add_argument("--evals", nargs="*", default=[], help="eval-NNN ids to emit")
    p.add_argument("--all", action="store_true", help="emit all evals in catalog")
    p.add_argument("--diff-from-stdin", action="store_true",
                   help="read changed files from stdin and route via eval_diff.py")
    p.add_argument("--catalog", default=str(CATALOG))
    p.add_argument("--out-dir", default="runs")
    args = p.parse_args()

    evals = parse_catalog(Path(args.catalog))
    selected: list[str]
    if args.all:
        selected = sorted(evals.keys())
    elif args.diff_from_stdin:
        selected = stdin_files_to_evals(Path("scripts/eval_diff.py"))
    else:
        selected = args.evals

    missing = [e for e in selected if e not in evals]
    if missing:
        sys.stderr.write(f"unknown evals: {missing}\n")
        return 2
    if not selected:
        sys.stderr.write("no evals selected\n")
        return 2

    run_id = f"{args.version}_{dt.datetime.utcnow().strftime('%Y%m%dT%H%M%S')}"
    out_dir = Path(args.out_dir) / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    written = []
    for evid in selected:
        contract = emit_contract(evals[evid], args.version)
        path = out_dir / f"{evid}.contract.json"
        path.write_text(
            json.dumps(contract, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        written.append(str(path))

    manifest = {
        "run_id": run_id,
        "version": args.version,
        "issued_at": dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "evals": selected,
        "contracts": written,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print(f"run_id: {run_id}")
    print(f"out_dir: {out_dir}")
    print(f"contracts: {len(written)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
