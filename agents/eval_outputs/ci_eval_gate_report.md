# CI Eval Gate Report

- Fecha: 2026-04-10T10:53:02.794598+00:00
- Total checks: 5
- Pass: 5
- Fail: 0

| Check | Estado | Descripción |
|---|---|---|
| eval-ci-001 | PASS | Todos los contratos con TASK_STATE declaran timeout_seconds en el schema de entrada. |
| eval-ci-002 | PASS | El orchestrator define timeout por fase y una salida explícita para timeouts. |
| eval-ci-003 | PASS | Auditor, QA y red_team recomputan verified_digest de forma independiente. |
| eval-ci-004 | PASS | Devops exige consenso de digests y revalida el payload stageado antes del commit. |
| eval-ci-005 | PASS | Los cambios en agents/*.agent.md disparan un gate automático de evals en CI. |

## Detalle

### eval-ci-001 — PASS
Todos los contratos con TASK_STATE declaran timeout_seconds en el schema de entrada.

- timeout_seconds presente en todos los contratos relevantes

### eval-ci-002 — PASS
El orchestrator define timeout por fase y una salida explícita para timeouts.

- Timeout gate documentado en orchestrator

### eval-ci-003 — PASS
Auditor, QA y red_team recomputan verified_digest de forma independiente.

- Las reglas de digest existen en los tres verificadores

### eval-ci-004 — PASS
Devops exige consenso de digests y revalida el payload stageado antes del commit.

- Gate de digest presente en devops

### eval-ci-005 — PASS
Los cambios en agents/*.agent.md disparan un gate automático de evals en CI.

- CI ejecuta el eval gate automático para contratos de agentes
