from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_verified_digest_module():
    script_path = Path(__file__).resolve().parents[3] / "scripts" / "verified_digest.py"
    spec = importlib.util.spec_from_file_location("verified_digest", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_compute_verified_digest_is_deterministic(tmp_path):
    module = _load_verified_digest_module()

    first = tmp_path / "b.txt"
    second_dir = tmp_path / "nested"
    second_dir.mkdir()
    second = second_dir / "a.txt"
    first.write_text("beta", encoding="utf-8")
    second.write_text("alpha", encoding="utf-8")

    result = module.compute_verified_digest(tmp_path, ["nested/a.txt", "b.txt"])

    assert result["files"] == ["b.txt", "nested/a.txt"]
    assert len(result["file_hashes"]) == 2
    assert len(result["verified_digest"]) == 64


def test_verify_report_consensus_detects_matching_reports(tmp_path):
    module = _load_verified_digest_module()

    tracked = tmp_path / "tracked.txt"
    tracked.write_text("payload", encoding="utf-8")

    computed = module.compute_verified_digest(tmp_path, ["tracked.txt"])
    report_body = (
        "<director_report>\n"
        "branch_name: feature/test\n"
        f"verified_digest: {computed['verified_digest']}\n"
        "</director_report>\n"
    )

    reports = []
    for index in range(3):
        report_path = tmp_path / f"report-{index}.txt"
        report_path.write_text(report_body, encoding="utf-8")
        reports.append(str(report_path))

    result = module.verify_report_consensus(
        workspace_root=tmp_path,
        file_paths=["tracked.txt"],
        report_paths=reports,
        expected_digest=computed["verified_digest"],
        expected_branch="feature/test",
    )

    assert result["success"] is True
    assert result["consensus_digest"] == computed["verified_digest"]
    assert result["errors"] == []