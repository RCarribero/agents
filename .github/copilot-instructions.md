# GitHub Copilot — Instrucciones del proyecto

## Stack y arquitectura

Este repositorio contiene el **sistema multi-agente v3**. El stack activo es:
- **Workspace local:** sistema de orquestación multi-agente y toolkit operativo basado en contratos Markdown, scripts Python/Bash/PowerShell y CI
- **Repos frontend objetivo:** Flutter/Dart con Riverpod, solo cuando el proyecto activo contenga `pubspec.yaml`
- **Agentes:** definidos en `agents/*.agent.md` — NO modificar sin autorización del orchestrator + eval gate
- **MCP:** configurado en `.mcp.json`; priorizar los servidores disponibles por tarea, sin depender de servicios HTTP locales del propio repo

## Convenciones de código — aplican solo si stack.md declara este lenguaje

### Python
- Mantener funciones pequeñas y cohesionadas; usar `async def` solo cuando el framework real del proyecto activo lo requiera
- No concatenar strings en queries SQL — usar parámetros siempre
- Variables de entorno via `os.getenv()` — nunca hardcodear claves
- Imports en orden: stdlib → terceros → locales

### Dart/Flutter
- Estas reglas aplican solo cuando el proyecto activo sea Flutter/Dart
- Riverpod para gestión de estado — no usar Provider directamente
- No estilos inline — usar `ThemeData` y `TextStyle` del sistema de diseño
- Widgets pequeños y reutilizables — preferred `shared/` si generalizable
- `flutter analyze --no-fatal-infos` debe pasar antes de cualquier entrega

### SQL / Migraciones
- Si la tarea requiere migraciones, ubicarlas en la ruta del proyecto activo con nombre `YYYYMMDD_NNN_descripcion.sql`
- Siempre idempotentes (IF NOT EXISTS, OR REPLACE)
- RLS obligatoria en tablas con datos de usuario cuando el stack de datos lo requiera
- Prohibido `USING (true)` sin comentario que justifique el caso público

## Sistema de agentes

- Cada agente tiene un contrato en `agents/*.agent.md`
- El flujo de ejecución: 0a → 0 → 1 → 2a → 2 → 3 (paralelo) → 4 → 5 (Fase -1 eliminada; usar prompt `/skill-installer` manualmente si se necesita skill_context)
- `skill_context` puede existir si el usuario ejecutó `/skill-installer` manualmente, pero no se espera ni bloquea su ausencia
- `devops` es el único agente con permisos git — nunca hacer commit desde otro contexto
- Triple aprobación obligatoria: `auditor` APROBADO + `qa` CUMPLE + `red_team` RESISTENTE
- `verified_digest` debe recomputarse independientemente por cada agente de Fase 3

## Commits

Seguir **Conventional Commits** estrictamente:
```
feat(scope): descripción
fix(scope): descripción
test(scope): descripción
refactor(scope): descripción
chore(scope): descripción
docs(scope): descripción
```

Incluir siempre trailer:
```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

Commits atómicos — un cambio lógico por commit.
DB migrations en commit separado (`feat(db):`) antes del commit de lógica cuando existan.

## Seguridad

- No exponer stack traces en respuestas o mensajes orientados a usuario
- No loguear tokens, keys ni PII en stdout/stderr
- En proyectos Flutter, eliminar `console.log/warn/error` en código de producción (configurar tree-shaking)
- Aplicar controles de permisos y políticas de datos según el backend real del proyecto activo

## Memoria y trazabilidad

- No asumir un servicio local de retrieval o indexación como prerequisito del ciclo
- `session_log.md` es audit-trail-artifact: NO incluir en `verified_files` ni en `verified_digest`

## Testing

- Tests deben estar en RED antes de que el implementador empiece (TDD)
- Cubrir: happy path + al menos 1 error + al menos 1 validación fallida
- No modificar tests existentes sin reportar el conflicto al orchestrator
- `run-tests.sh --json` retorna resultado estructurado para consumo de agentes

## MCP

- **MCP locales del repo** — definidos en `.mcp.json`: filesystem, GitHub, Postgres u otros según el workspace. Usar solo los que la tarea necesite.
- **MCP del perfil global** — sincronizados por `install-copilot-layout` cuando el layout está instalado: GitHub (`io.github.github/github-mcp-server`), Supabase (`com.supabase/mcp`), Vercel (`com.vercel/vercel-mcp`), Stripe (`com.resend/mcp`). Solo usar si están efectivamente disponibles en la sesión; no asumir disponibilidad ciega.
- No hardcodear credenciales ni URLs de servicios en instrucciones o scripts

## Pull Requests

- Descripción debe incluir: qué cambió, por qué, cómo probar, agentes involucrados
- Relacionar el PR con el `task_id` del ciclo (`task: xxxxxx`)
- No mergear sin triple aprobación de Fase 3 documentada en el PR

## Prompts disponibles

- **`/skill-installer`** (`prompts/skill-installer.prompt.md`) — detecta el stack del proyecto activo y construye el `skill_context`; invocar manualmente antes de una sesión de trabajo nueva o tras cambios de stack.
- **`/dockerize`** (`prompts/dockerize.prompt.md`) — dockeriza el proyecto activo (Dockerfile multi-stage, docker-compose, .dockerignore) + setup local del entorno + carpeta `docker-launcher/` con scripts de setup/build/launch para Bash y PowerShell.
