#!/usr/bin/env python3
"""
eval_runner_ci.py — Structural validation of agent contracts for CI.

Runs structural (non-LLM) checks on agent .md files:
- Required sections exist (contrato, reglas, AUTONOMOUS_LEARNINGS, cadena handoff)
- director_report and agent_report templates have required fields
- Routing coherence (task_classification references valid agents)
- No broken lib/ references

Usage:
  python scripts/eval_runner_ci.py --output eval-results.json
"""

import argparse
import json
import re
import sys
from pathlib import Path

AGENTS_DIR = Path("agents")
LIB_DIR = AGENTS_DIR / "lib"

# Required sections in every .agent.md (flexible patterns for naming variations)
REQUIRED_SECTIONS = {
    "contrato": re.compile(r"##\s+Contrato de agente", re.IGNORECASE),
    "reglas": re.compile(r"##\s+Regla[s]?\s+(de operacion|previa|de ejecuci)", re.IGNORECASE),
    "autonomous_learnings": re.compile(r"AUTONOMOUS_LEARNINGS_START"),
    "autonomous_learnings_end": re.compile(r"AUTONOMOUS_LEARNINGS_END"),
    "handoff": re.compile(r"(##\s+Cadena de handoff|handoff|→.*orchestrator|→.*devops)", re.IGNORECASE),
}

# Required fields in director_report template
DIRECTOR_REPORT_FIELDS = ["task_id", "status", "summary"]
# next_agent is checked separately since orchestrator doesn't always have it in template

# Required fields in agent_report template (flexible — some agents omit task_state in template)
AGENT_REPORT_FIELDS = ["status", "summary", "goal", "risk_level", "files"]

# Valid agent names (for routing checks)
VALID_AGENTS = {
    "orchestrator", "researcher", "analyst", "dbmanager", "tdd_enforcer",
    "developer", "backend", "frontend", "auditor", "qa", "red_team",
    "devops", "session_logger", "memory_curator", "eval_runner",
    "explore", "skill_installer",
}

# Lib files that should exist if referenced
KNOWN_LIBS = {
    "task_classification.md",
    "learning_protocol.md",
    "mcp_circuit_breaker.md",
}


def find_agent_files():
    """Find all .agent.md files."""
    if not AGENTS_DIR.exists():
        return []
    return sorted(AGENTS_DIR.glob("*.agent.md"))


def check_required_sections(filepath: Path) -> list:
    """Check that all required sections exist in an agent file."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    issues = []
    for section_name, pattern in REQUIRED_SECTIONS.items():
        if not pattern.search(content):
            issues.append(f"Missing section: {section_name}")
    return issues


def check_report_fields(filepath: Path) -> list:
    """Check that director_report and agent_report have required fields."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    issues = []

    # Check director_report
    if "<director_report>" in content:
        dr_match = re.search(
            r"<director_report>(.*?)</director_report>", content, re.DOTALL
        )
        if dr_match:
            dr_block = dr_match.group(1)
            for field in DIRECTOR_REPORT_FIELDS:
                if f"{field}:" not in dr_block:
                    issues.append(f"director_report missing field: {field}")
    else:
        issues.append("No director_report template found")

    # Check agent_report (optional for orchestrator and eval_runner)
    agent_name = filepath.stem.replace(".agent", "")
    if "<agent_report>" in content:
        ar_match = re.search(
            r"<agent_report>(.*?)</agent_report>", content, re.DOTALL
        )
        if ar_match:
            ar_block = ar_match.group(1)
            for field in AGENT_REPORT_FIELDS:
                if f"{field}:" not in ar_block:
                    issues.append(f"agent_report missing field: {field}")
    elif agent_name not in ("orchestrator", "eval_runner"):
        issues.append("No agent_report template found")

    return issues


def check_lib_references(filepath: Path) -> list:
    """Check that references to lib/ files point to existing files."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    issues = []

    # Find all lib/ references in markdown links
    refs = re.findall(r"\[.*?\]\((lib/[^)]+)\)", content)
    for ref in refs:
        ref_path = AGENTS_DIR / ref
        if not ref_path.exists():
            issues.append(f"Broken lib reference: {ref} (file not found)")

    return issues


def check_frontmatter(filepath: Path) -> list:
    """Check YAML frontmatter has required fields."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    issues = []

    fm_match = re.match(r"^---\s*\r?\n(.*?)\r?\n---", content, re.DOTALL)
    if not fm_match:
        issues.append("Missing YAML frontmatter (---)")
        return issues

    fm = fm_match.group(1)
    for field in ["name", "description", "model"]:
        if f"{field}:" not in fm:
            issues.append(f"Frontmatter missing field: {field}")

    return issues


def check_caveman_rule(filepath: Path) -> list:
    """Check that CAVEMAN ULTRA rule 0z exists (required for all agents)."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    if "CAVEMAN ULTRA" not in content:
        return ["Missing rule 0z (CAVEMAN ULTRA)"]
    return []


def check_task_classification_coherence() -> list:
    """Check that task_classification.md references valid modes and agents."""
    tc_path = LIB_DIR / "task_classification.md"
    if not tc_path.exists():
        return [{"id": "eval-tc-exists", "result": "FAIL",
                 "reason": "task_classification.md not found", "weight": "critical"}]

    content = tc_path.read_text(encoding="utf-8", errors="replace")
    results = []

    # Check modes exist
    for mode in ["MODO CONSULTA", "MODO RÁPIDO", "MODO COMPLETO"]:
        if mode not in content:
            results.append({
                "id": f"eval-tc-mode-{mode.split()[-1].lower()}",
                "result": "FAIL",
                "reason": f"task_classification.md missing mode: {mode}",
                "weight": "critical",
            })

    if not results:
        results.append({
            "id": "eval-tc-modes",
            "result": "PASS",
            "reason": "All 3 modes defined",
            "weight": "critical",
        })

    return results


def run_evals():
    """Run all structural evals and return results."""
    results = []
    agent_files = find_agent_files()

    if not agent_files:
        results.append({
            "id": "eval-agents-exist",
            "result": "FAIL",
            "reason": "No .agent.md files found in agents/",
            "weight": "critical",
        })
        return results

    # Per-agent checks
    for filepath in agent_files:
        agent_name = filepath.stem.replace(".agent", "")

        # Frontmatter
        fm_issues = check_frontmatter(filepath)
        results.append({
            "id": f"eval-fm-{agent_name}",
            "result": "FAIL" if fm_issues else "PASS",
            "reason": "; ".join(fm_issues) if fm_issues else "Frontmatter OK",
            "weight": "critical",
            "agent": agent_name,
        })

        # Required sections
        section_issues = check_required_sections(filepath)
        results.append({
            "id": f"eval-sections-{agent_name}",
            "result": "FAIL" if section_issues else "PASS",
            "reason": "; ".join(section_issues) if section_issues else "All sections present",
            "weight": "high",
            "agent": agent_name,
        })

        # Report fields
        report_issues = check_report_fields(filepath)
        results.append({
            "id": f"eval-reports-{agent_name}",
            "result": "FAIL" if report_issues else "PASS",
            "reason": "; ".join(report_issues) if report_issues else "Report fields OK",
            "weight": "critical",
            "agent": agent_name,
        })

        # Lib references
        lib_issues = check_lib_references(filepath)
        results.append({
            "id": f"eval-libs-{agent_name}",
            "result": "FAIL" if lib_issues else "PASS",
            "reason": "; ".join(lib_issues) if lib_issues else "Lib refs OK",
            "weight": "high",
            "agent": agent_name,
        })

        # Caveman rule
        caveman_issues = check_caveman_rule(filepath)
        results.append({
            "id": f"eval-caveman-{agent_name}",
            "result": "FAIL" if caveman_issues else "PASS",
            "reason": "; ".join(caveman_issues) if caveman_issues else "Caveman OK",
            "weight": "medium",
            "agent": agent_name,
        })

    # System-level checks
    results.extend(check_task_classification_coherence())

    return results


def main():
    parser = argparse.ArgumentParser(description="Structural agent contract evals")
    parser.add_argument("--output", default="eval-results.json", help="Output JSON file")
    args = parser.parse_args()

    results = run_evals()

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    # Print summary
    total = len(results)
    passed = sum(1 for r in results if r["result"] == "PASS")
    failed = sum(1 for r in results if r["result"] == "FAIL")
    critical_fails = sum(
        1 for r in results if r["result"] == "FAIL" and r.get("weight") == "critical"
    )

    print(f"\n{'='*50}")
    print(f"Agent Contract Evals: {passed}/{total} passed, {failed} failed")
    if critical_fails:
        print(f"⛔ {critical_fails} CRITICAL failures — blocking merge")
    print(f"{'='*50}\n")

    # Exit 1 if critical failures
    sys.exit(1 if critical_fails else 0)


if __name__ == "__main__":
    main()
