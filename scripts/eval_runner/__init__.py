"""scripts.eval_runner - deterministic scorer for eval contracts.

Reads contract + captured agent output, scores each criterion via simple regex,
emits PASS/FAIL/PARTIAL JSON. No LLM-as-judge.
"""
