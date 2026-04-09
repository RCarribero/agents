#!/usr/bin/env python
"""Gate automático de evals contractuales para PRs que tocan agents/*.agent.md."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import sys


@dataclass
class CheckResult:
    check_id: str
    description: str
    passed: bool
    details: list[str]


def _read_text(root: Path, relative_path: str) -> str:
    return (root / relative_path).read_text(encoding="utf-8", errors="replace")


def _resolve_workflow_path(root: Path) -> Path | None:
    candidates = [
        root / ".github/workflows/ci.yml",
        root / "workflows/ci.yml",
    ]

    for candidate in candidates:
        if candidate.is_file():
            return candidate

    return None


def _contains_all(text: str, tokens: list[str]) -> tuple[bool, list[str]]:
    missing = [token for token in tokens if token not in text]
    return not missing, missing


def _check_task_state_timeout(root: Path) -> CheckResult:
    failures: list[str] = []

    for agent_file in sorted((root / "agents").glob("*.agent.md")):
        text = agent_file.read_text(encoding="utf-8", errors="replace")
        if '"task_state": {' in text and '"timeout_seconds": 0' not in text:
            failures.append(f"{agent_file.relative_to(root).as_posix()}: task_state sin timeout_seconds")

    return CheckResult(
        check_id="eval-ci-001",
        description="Todos los contratos con TASK_STATE declaran timeout_seconds en el schema de entrada.",
        passed=not failures,
        details=failures or ["timeout_seconds presente en todos los contratos relevantes"],
    )


def _check_orchestrator_timeout_gate(root: Path) -> CheckResult:
    text = _read_text(root, "agents/orchestrator.agent.md")
    passed, missing = _contains_all(text, ["timeout_seconds", "PHASE_TIMEOUT", "Ninguna fase puede quedar esperando indefinidamente"])
    return CheckResult(
        check_id="eval-ci-002",
        description="El orchestrator define timeout por fase y una salida explícita para timeouts.",
        passed=passed,
        details=[f"Falta token: {token}" for token in missing] or ["Timeout gate documentado en orchestrator"],
    )


def _check_phase3_digest_rules(root: Path) -> CheckResult:
    failures: list[str] = []
    for relative_path in ["agents/auditor.agent.md", "agents/qa.agent.md", "agents/red_team.agent.md"]:
        text = _read_text(root, relative_path)
        passed, missing = _contains_all(text, ["REGLA DE DIGEST", "verified_digest"])
        if not passed:
            failures.append(f"{relative_path}: faltan {', '.join(missing)}")

    return CheckResult(
        check_id="eval-ci-003",
        description="Auditor, QA y red_team recomputan verified_digest de forma independiente.",
        passed=not failures,
        details=failures or ["Las reglas de digest existen en los tres verificadores"],
    )


def _check_devops_digest_gate(root: Path) -> CheckResult:
    text = _read_text(root, "agents/devops.agent.md")
    passed, missing = _contains_all(
        text,
        [
            "Verificación cruzada de digests de los tres reports",
            "staged-payload digest mismatch",
            "verified_digest mismatch",
        ],
    )
    return CheckResult(
        check_id="eval-ci-004",
        description="Devops exige consenso de digests y revalida el payload stageado antes del commit.",
        passed=passed,
        details=[f"Falta token: {token}" for token in missing] or ["Gate de digest presente en devops"],
    )


def _check_eval_runner_ci_bridge(root: Path) -> CheckResult:
    eval_runner = _read_text(root, "agents/eval_runner.agent.md")
    workflow_path = _resolve_workflow_path(root)
    workflow = workflow_path.read_text(encoding="utf-8", errors="replace") if workflow_path else ""

    failures: list[str] = []
    if "Timeout estricto de 5 minutos por eval" not in eval_runner:
        failures.append("agents/eval_runner.agent.md: falta la regla de timeout estricto")
    if workflow_path is None:
        failures.append("workflows/ci.yml: no se encontró workflow CI en la ruta nueva ni en .github/workflows/ci.yml")
    elif "run_eval_gate.py" not in workflow or "eval-gate:" not in workflow:
        failures.append(f"{workflow_path.relative_to(root).as_posix()}: falta el job eval-gate o la invocación a run_eval_gate.py")

    return CheckResult(
        check_id="eval-ci-005",
        description="Los cambios en agents/*.agent.md disparan un gate automático de evals en CI.",
        passed=not failures,
        details=failures or ["CI ejecuta el eval gate automático para contratos de agentes"],
    )


def _render_report(results: list[CheckResult], report_path: Path) -> None:
    passed = sum(1 for result in results if result.passed)
    total = len(results)
    lines = [
        "# CI Eval Gate Report",
        "",
        f"- Fecha: {datetime.now(timezone.utc).isoformat()}",
        f"- Total checks: {total}",
        f"- Pass: {passed}",
        f"- Fail: {total - passed}",
        "",
        "| Check | Estado | Descripción |",
        "|---|---|---|",
    ]

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        lines.append(f"| {result.check_id} | {status} | {result.description} |")

    lines.append("")
    lines.append("## Detalle")
    lines.append("")

    for result in results:
        lines.append(f"### {result.check_id} — {'PASS' if result.passed else 'FAIL'}")
        lines.append(result.description)
        lines.append("")
        for detail in result.details:
            lines.append(f"- {detail}")
        lines.append("")

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Ejecuta checks automáticos sobre contratos de agentes.")
    parser.add_argument("--root", default=".")
    parser.add_argument("--report-file", default="agents/eval_outputs/ci_eval_gate_report.md")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    report_path = (root / args.report_file).resolve()

    results = [
        _check_task_state_timeout(root),
        _check_orchestrator_timeout_gate(root),
        _check_phase3_digest_rules(root),
        _check_devops_digest_gate(root),
        _check_eval_runner_ci_bridge(root),
    ]

    _render_report(results, report_path)

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.check_id} - {result.description}")
        for detail in result.details:
            print(f"  - {detail}")

    return 0 if all(result.passed for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())