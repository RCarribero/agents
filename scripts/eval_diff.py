#!/usr/bin/env python3
"""
eval_diff.py — Resolve which evals to run given a set of changed files.

Reads the mapping table from `agents/evals/eval_catalog.md` (section
"## Mapping eval ↔ agentes cubiertos") and intersects changed agents
against each eval's covered agents.

Usage:
  python scripts/eval_diff.py --files agents/orchestrator.agent.md agents/qa.agent.md
  git diff --name-only HEAD~1 | python scripts/eval_diff.py --stdin

Output:
  JSON to stdout: {"changed_agents": [...], "evals_to_run": [...], "groups": [...]}

Exit codes:
  0 = at least one eval matched (or --allow-empty)
  2 = no evals matched and --allow-empty not set
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CATALOG = Path("agents/evals/eval_catalog.md")
ROW_RE = re.compile(r"^\|\s*(eval-\d{3})\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$")
AGENT_RE = re.compile(r"agents/([a-z_]+)\.agent\.md", re.IGNORECASE)


def load_mapping(catalog: Path) -> list[dict]:
    if not catalog.exists():
        sys.stderr.write(f"catalog not found: {catalog}\n")
        sys.exit(3)
    rows = []
    in_table = False
    for line in catalog.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("| Eval "):
            in_table = True
            continue
        if in_table:
            if not line.strip().startswith("|"):
                break
            if line.strip().startswith("|---"):
                continue
            m = ROW_RE.match(line)
            if not m:
                continue
            eval_id, agents_csv, group = m.groups()
            agents = [a.strip() for a in agents_csv.split(",") if a.strip()]
            rows.append({"eval_id": eval_id, "agents": agents, "group": group.strip()})
    return rows


def changed_agents_from_files(files: list[str]) -> list[str]:
    out = set()
    for f in files:
        m = AGENT_RE.search(f.replace("\\", "/"))
        if m:
            out.add(m.group(1).lower())
        # lib/ changes => run everything that depends on routing/contracts
        if "/lib/task_classification" in f.replace("\\", "/"):
            out.add("orchestrator")
        if "/lib/caveman_protocol" in f.replace("\\", "/"):
            out.add("__caveman__")
    return sorted(out)


def select_evals(rows: list[dict], changed: list[str]) -> tuple[list[str], list[str]]:
    if "__caveman__" in changed:
        return [r["eval_id"] for r in rows], sorted({r["group"] for r in rows})
    selected = []
    groups = set()
    changed_set = set(changed)
    for r in rows:
        if changed_set.intersection({a.lower() for a in r["agents"]}):
            selected.append(r["eval_id"])
            groups.add(r["group"])
    return selected, sorted(groups)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--files", nargs="*", default=[])
    p.add_argument("--stdin", action="store_true", help="read filenames from stdin")
    p.add_argument("--catalog", default=str(CATALOG))
    p.add_argument("--allow-empty", action="store_true")
    args = p.parse_args()

    files = list(args.files)
    if args.stdin:
        files.extend(line.strip() for line in sys.stdin if line.strip())

    rows = load_mapping(Path(args.catalog))
    changed = changed_agents_from_files(files)
    evals, groups = select_evals(rows, changed)

    json.dump(
        {"changed_agents": changed, "evals_to_run": evals, "groups": groups},
        sys.stdout,
        indent=2,
        ensure_ascii=False,
    )
    sys.stdout.write("\n")

    if not evals and not args.allow_empty:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
