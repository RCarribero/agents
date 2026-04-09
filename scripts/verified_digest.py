#!/usr/bin/env python
"""Utilidades canónicas para calcular y verificar verified_digest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Sequence


def _resolve_file_path(workspace_root: Path, file_path: str) -> tuple[str, Path]:
    candidate = Path(file_path)
    absolute = candidate if candidate.is_absolute() else (workspace_root / candidate)
    absolute = absolute.resolve()
    workspace_root = workspace_root.resolve()

    try:
        relative = absolute.relative_to(workspace_root).as_posix()
    except ValueError as exc:
        raise ValueError(f"El archivo queda fuera del workspace: {file_path}") from exc

    if not absolute.is_file():
        raise FileNotFoundError(f"Archivo no encontrado: {relative}")

    return relative, absolute


def compute_verified_digest(workspace_root: Path, file_paths: Sequence[str]) -> dict:
    resolved_files = [_resolve_file_path(workspace_root, file_path) for file_path in file_paths]
    resolved_files.sort(key=lambda item: item[0])

    per_file: list[dict[str, str]] = []
    digest_input = ""

    for relative_path, absolute_path in resolved_files:
        file_digest = hashlib.sha256(absolute_path.read_bytes()).hexdigest()
        per_file.append({"path": relative_path, "sha256": file_digest})
        digest_input += file_digest

    verified_digest = hashlib.sha256(digest_input.encode("ascii")).hexdigest()

    return {
        "workspace_root": str(workspace_root.resolve()),
        "files": [item["path"] for item in per_file],
        "file_hashes": per_file,
        "verified_digest": verified_digest,
    }


def _extract_report_field(report_text: str, field_name: str) -> str | None:
    pattern = re.compile(rf"^\s*{re.escape(field_name)}:\s*(.+?)\s*$", re.MULTILINE)
    match = pattern.search(report_text)
    return match.group(1).strip() if match else None


def verify_report_consensus(
    workspace_root: Path,
    file_paths: Sequence[str],
    report_paths: Sequence[str],
    expected_digest: str | None = None,
    expected_branch: str | None = None,
) -> dict:
    computed = compute_verified_digest(workspace_root, file_paths)
    reports: list[dict[str, str | bool | None]] = []
    digest_values: list[str] = []
    branch_values: list[str] = []
    errors: list[str] = []

    for report_path in report_paths:
        report_file = Path(report_path)
        report_text = report_file.read_text(encoding="utf-8", errors="replace")
        report_digest = _extract_report_field(report_text, "verified_digest")
        report_branch = _extract_report_field(report_text, "branch_name")

        reports.append(
            {
                "report": str(report_file),
                "verified_digest": report_digest,
                "branch_name": report_branch,
                "has_digest": bool(report_digest),
            }
        )

        if not report_digest:
            errors.append(f"{report_file}: falta verified_digest")
        else:
            digest_values.append(report_digest)

        if expected_branch:
            if not report_branch:
                errors.append(f"{report_file}: falta branch_name")
            else:
                branch_values.append(report_branch)

    consensus_digest = digest_values[0] if digest_values and len(set(digest_values)) == 1 else None

    if digest_values and len(set(digest_values)) != 1:
        errors.append("Los reports no comparten el mismo verified_digest")

    if expected_digest and consensus_digest and consensus_digest != expected_digest:
        errors.append("El digest consensuado no coincide con expected_digest")

    if consensus_digest and consensus_digest != computed["verified_digest"]:
        errors.append("El digest consensuado no coincide con el contenido actual del workspace")

    if expected_branch and branch_values and len(set(branch_values)) != 1:
        errors.append("Los reports no comparten el mismo branch_name")

    if expected_branch and branch_values and branch_values[0] != expected_branch:
        errors.append("El branch_name consensuado no coincide con expected_branch")

    success = not errors and consensus_digest is not None

    return {
        "success": success,
        "computed": computed,
        "consensus_digest": consensus_digest,
        "expected_digest": expected_digest,
        "expected_branch": expected_branch,
        "reports": reports,
        "errors": errors,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Calcula y valida verified_digest.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    compute_parser = subparsers.add_parser("compute", help="Calcula verified_digest para un conjunto de archivos")
    compute_parser.add_argument("--workspace-root", default=".")
    compute_parser.add_argument("files", nargs="+", help="Archivos incluidos en verified_files")

    verify_parser = subparsers.add_parser("verify-consensus", help="Valida consenso entre reports de Fase 3")
    verify_parser.add_argument("--workspace-root", default=".")
    verify_parser.add_argument("--expected-digest")
    verify_parser.add_argument("--expected-branch")
    verify_parser.add_argument("--report", dest="reports", action="append", required=True)
    verify_parser.add_argument("files", nargs="+", help="Archivos incluidos en verified_files")

    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    workspace_root = Path(args.workspace_root)

    try:
        if args.command == "compute":
            result = compute_verified_digest(workspace_root, args.files)
            print(json.dumps(result, indent=2, ensure_ascii=False))
            return 0

        result = verify_report_consensus(
            workspace_root=workspace_root,
            file_paths=args.files,
            report_paths=args.reports,
            expected_digest=args.expected_digest,
            expected_branch=args.expected_branch,
        )
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if result["success"] else 1
    except Exception as exc:
        print(json.dumps({"success": False, "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())