# GitHub Copilot — Instrucciones del proyecto

## Stack y arquitectura

Este repositorio contiene el **sistema multi-agente v3**. El stack activo es:
- **Workspace local:** sistema de orquestación multi-agente + API embebida en `agents/api` (FastAPI + Python 3.11 + Supabase)
- **Repos frontend objetivo:** Flutter/Dart con Riverpod, solo cuando el proyecto activo contenga `pubspec.yaml`
- **Agentes:** definidos en `agents/*.agent.md` — NO modificar sin autorización del orchestrator + eval gate
- **MCP:** configurado en `.mcp.json`; usar tools MCP en lugar de acceso directo al filesystem cuando sea posible

## Convenciones de código — aplican solo si stack.md declara este lenguaje

### Python (FastAPI)
- Usar `async def` en todos los endpoints
- Pydantic v2 para validación — no usar `validator`, usar `field_validator`
- Usar `Depends()` para inyección de dependencias
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
- Migraciones en `agents/api/migrations/` con nombre `YYYYMMDD_NNN_descripcion.sql`
- Siempre idempotentes (IF NOT EXISTS, OR REPLACE)
- RLS obligatoria en todas las tablas con datos de usuario
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
DB migrations en commit separado (`feat(db):`) antes del commit de lógica.

## Seguridad

- No exponer stack traces en responses de la API — mapear a mensajes genéricos
- No loguear tokens, keys ni PII en stdout/stderr
- En proyectos Flutter, eliminar `console.log/warn/error` en código de producción (configurar tree-shaking)
- RLS debe estar activa en todas las tablas Supabase antes de cualquier query

## RAG y memoria

- Usar `/mcp/tools/call` con `retrieve_context` para enriquecer contexto antes de planificar
- Indexar documentos nuevos con `embed_document` tras cada ciclo exitoso
- Limitar a k=5 en retrieval para controlar tokens (k=10 solo si el contexto es muy amplio)
- `session_log.md` es audit-trail-artifact: NO incluir en `verified_files` ni en `verified_digest`

## Testing

- Tests deben estar en RED antes de que el implementador empiece (TDD)
- Cubrir: happy path + al menos 1 error + al menos 1 validación fallida
- No modificar tests existentes sin reportar el conflicto al orchestrator
- `run-tests.sh --json` retorna resultado estructurado para consumo de agentes

## MCP

- Usar herramientas del filesystem MCP server en lugar de leer archivos con contexto manual
- El servidor `agents-api` expone `/mcp/tools` — consultarlo antes de implementar integraciones
- `AGENTS_API_URL` y `AGENTS_API_KEY` deben estar en `.env` — no hardcodear

## Pull Requests

- Descripción debe incluir: qué cambió, por qué, cómo probar, agentes involucrados
- Relacionar el PR con el `task_id` del ciclo (`task: xxxxxx`)
- No mergear sin triple aprobación de Fase 3 documentada en el PR

## Prompts disponibles

- **`/skill-installer`** (`prompts/skill-installer.prompt.md`) — detecta el stack del proyecto activo y construye el `skill_context`; invocar manualmente antes de una sesión de trabajo nueva o tras cambios de stack.
