# Stack del Proyecto

**Curado manualmente** — 2026-04-10

## Scope activo

- Workspace raíz: repositorio de orquestación multi-agente
- Toolkit operativo: contratos en `agents/`, scripts en `scripts/`, prompts y CI en `.github/`
- Scripts de validación desde raíz: `scripts/run-tests/run-tests.sh . --json`, `scripts/run-lint/run-lint.sh . --json`, `python scripts/run_eval_gate.py --root .`

## Stack local

```text
markdown, python, bash, powershell
```

## Convenciones importantes

- Este workspace no mantiene backend embebido ni migraciones propias.
- En esta raíz toolkit, `scripts/run-tests/run-tests.sh . --json` ejecuta el eval gate sin escribir reporte persistente y `scripts/run-lint/run-lint.sh . --json` ejecuta `validate-agents` + `token-report`.
- Las reglas de Flutter/Riverpod solo aplican cuando el proyecto activo de la tarea tenga `pubspec.yaml`.
- `session_log.md` es artefacto append-only y no entra en `verified_digest`.