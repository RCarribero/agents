# Stack del Proyecto

**Curado manualmente** — 2026-04-09

## Scope activo

- Workspace raíz: repositorio de orquestación multi-agente
- Backend embebido: `agents/api`
- Scripts de validación desde raíz: `scripts/run-tests.sh . --json`, `scripts/run-lint.sh . --json`

## Stack local

```text
python, fastapi, supabase, bash
```

## Convenciones importantes

- Las migraciones de este workspace viven en `agents/api/migrations/`
- Las reglas de Flutter/Riverpod solo aplican cuando el proyecto activo de la tarea tenga `pubspec.yaml`
- `session_log.md` es artefacto append-only y no entra en `verified_digest`