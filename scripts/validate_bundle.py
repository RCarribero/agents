#!/usr/bin/env python3
"""
validate_bundle.py — Valida el consenso entre los tres director_reports de Fase 3
antes de habilitar Fase 4 (devops).

Uso:
  python scripts/validate_bundle.py \
      --auditor auditor_report.txt \
      --qa qa_report.txt \
      --redteam redteam_report.txt \
      --task-id <task_id_base> \
      [--invocation-cycle <verification_cycle_esperado>] \
      [--invocation-branch <branch_name_esperado>] \
      [--invocation-digest <verified_digest_esperado>]

Salida:
  Exit 0 si bundle válido (consenso completo + match con invocación si se pasó).
  Exit 1 con mensaje en stderr si hay cualquier divergencia.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED_FIELDS = (
    "task_id",
    "verification_cycle",
    "verified_files",
    "branch_name",
    "verified_digest",
)


def parse_report(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for key in REQUIRED_FIELDS + ("test_status", "eval_gate_status"):
        m = re.search(rf"^\s*{re.escape(key)}\s*:\s*(.+)$", text, flags=re.MULTILINE)
        if m:
            out[key] = m.group(1).strip()
    return out


def normalize_files(value: str) -> frozenset[str]:
    items = [v.strip().replace("\\", "/") for v in re.split(r"[,\n]", value) if v.strip()]
    return frozenset(items)


def base_task_id(task_id: str) -> str:
    return re.sub(r"\.(audit|qa|redteam)$", "", task_id)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--auditor", required=True, type=Path)
    ap.add_argument("--qa", required=True, type=Path)
    ap.add_argument("--redteam", required=True, type=Path)
    ap.add_argument("--task-id", required=True, help="task_id base esperado")
    ap.add_argument("--invocation-cycle", default=None)
    ap.add_argument("--invocation-branch", default=None)
    ap.add_argument("--invocation-digest", default=None)
    args = ap.parse_args()

    reports = {
        "auditor": parse_report(args.auditor),
        "qa": parse_report(args.qa),
        "redteam": parse_report(args.redteam),
    }

    errors: list[str] = []

    # 1. Todos deben emitir los campos requeridos.
    for name, rep in reports.items():
        for field in REQUIRED_FIELDS:
            if field not in rep:
                errors.append(f"{name}: missing field '{field}'")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    # 2. task_id base debe coincidir con --task-id.
    for name, rep in reports.items():
        if base_task_id(rep["task_id"]) != args.task_id:
            errors.append(
                f"{name}: task_id base '{base_task_id(rep['task_id'])}' != esperado '{args.task_id}'"
            )

    # 3. verification_cycle igual en los tres y prefijo == task_id base.
    cycles = {n: r["verification_cycle"] for n, r in reports.items()}
    if len(set(cycles.values())) != 1:
        errors.append(f"verification_cycle divergente: {cycles}")
    cycle = next(iter(cycles.values()))
    if not cycle.startswith(args.task_id + "."):
        errors.append(
            f"verification_cycle '{cycle}' no deriva del task_id base '{args.task_id}'"
        )

    # 4. verified_files igualdad exacta como conjunto.
    file_sets = {n: normalize_files(r["verified_files"]) for n, r in reports.items()}
    ref = next(iter(file_sets.values()))
    for n, fs in file_sets.items():
        if fs != ref:
            errors.append(f"verified_files divergente en {n}: {sorted(fs)} vs {sorted(ref)}")
    if "session_log.md" in {p.split("/")[-1] for p in ref}:
        errors.append("verified_files contiene session_log.md (debe estar excluido)")

    # 5. branch_name igual en los tres.
    branches = {n: r["branch_name"] for n, r in reports.items()}
    if len(set(branches.values())) != 1:
        errors.append(f"branch_name divergente: {branches}")

    # 6. verified_digest idéntico en los tres.
    digests = {n: r["verified_digest"] for n, r in reports.items()}
    if len(set(digests.values())) != 1:
        errors.append(f"verified_digest divergente: {digests}")

    # 7. Match contra invocación de devops si se pasó.
    if args.invocation_cycle and cycle != args.invocation_cycle:
        errors.append(
            f"verification_cycle bundle '{cycle}' != invocación '{args.invocation_cycle}'"
        )
    if args.invocation_branch:
        b = next(iter(branches.values()))
        if b != args.invocation_branch:
            errors.append(f"branch_name bundle '{b}' != invocación '{args.invocation_branch}'")
    if args.invocation_digest:
        d = next(iter(digests.values()))
        if d != args.invocation_digest:
            errors.append(f"verified_digest bundle '{d}' != invocación '{args.invocation_digest}'")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print("BUNDLE_VALID")
    return 0


if __name__ == "__main__":
    sys.exit(main())
