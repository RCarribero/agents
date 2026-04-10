# Stack del Proyecto

**Curado manualmente** — 2026-04-10

## Scope activo

- Workspace raíz: repositorio de orquestación multi-agente
- Toolkit operativo: contratos en `agents/`, scripts en `scripts/`, prompts y CI en `.github/`
- Bootstrap desde raíz: `/start` o `scripts/start/start.*` crean `stack.md` si falta

## Stack local

```text
markdown, python, bash, powershell
```

## Convenciones importantes

- Este workspace no mantiene backend embebido ni migraciones propias.
- En esta raíz toolkit, la verificación se apoya en el flujo del swarm, la documentación operativa y las herramientas nativas del proyecto activo.
- Las reglas de Flutter/Riverpod solo aplican cuando el proyecto activo de la tarea tenga `pubspec.yaml`.
- `session_log.md` es artefacto append-only y no entra en `verified_digest`.