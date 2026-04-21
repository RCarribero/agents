# Protocolo de Circuit Breaker para MCPs

Define el modo de degradación elegante cuando un MCP server falla o no responde.

---

## Problema que resuelve

Sin este protocolo, si un MCP (GitHub, Supabase, Vercel) falla:
- El agente se bloquea indefinidamente esperando respuesta
- No hay fallback a herramientas CLI equivalentes
- El ciclo completo se pierde y requiere intervención humana

## Estados del circuit breaker

```
     ┌─────────┐    2+ fallos consecutivos    ┌─────────┐
     │ CLOSED  │ ─────────────────────────────▶│  OPEN   │
     │ (normal)│                               │(fallback│
     └────┬────┘                               └────┬────┘
          │                                         │
          │◀──── probe OK ─────┐                    │
          │                    │                    │
                          ┌────┴────┐               │
                          │  HALF   │◀──── 5 min ───┘
                          │ (probe) │
                          └─────────┘
```

| Estado | Comportamiento | Transición |
|--------|---------------|------------|
| `CLOSED` | Usar MCP normalmente | → `OPEN` tras 2+ fallos consecutivos |
| `OPEN` | Usar fallback CLI | → `HALF` tras 5 minutos |
| `HALF` | Intentar 1 request MCP de prueba | → `CLOSED` si OK, → `OPEN` si falla |

## Fallbacks por MCP

### GitHub MCP (`mcp_io_github_git_*`)
- **Fallback**: `git` CLI local para commit, branch, status, push
- **PR creation**: `gh pr create` si `gh` CLI disponible; si no → skip PR, reportar `MCP_DEGRADED`
- **Detección de fallo**: timeout >10s en cualquier `mcp_io_github_git_*` o error de conexión

### Supabase MCP (`mcp_supabase-mcp-server_*`)
- **Fallback**: `psql` directo si `POSTGRES_DB_URL` disponible en `.env`
- **Si no hay URL directa**: skip la operación DB, reportar `MCP_DEGRADED`
- **Detección de fallo**: timeout >15s o error en `execute_sql` / `apply_migration`

### Vercel MCP (si configurado)
- **Fallback**: skip deployment, reportar `MCP_DEGRADED`
- **Detección de fallo**: timeout >20s o error de conexión

### Filesystem MCP
- **Sin fallback necesario**: siempre disponible localmente
- **Si falla**: `ESCALATE → human` (indica problema grave del sistema)

## TASK_STATE: campo `mcp_status`

El orchestrator inicializa y mantiene el campo `mcp_status` en TASK_STATE:

```json
{
  "mcp_status": {
    "github": { "state": "CLOSED", "fail_count": 0, "last_fail": null, "last_probe": null },
    "supabase": { "state": "CLOSED", "fail_count": 0, "last_fail": null, "last_probe": null },
    "vercel": { "state": "CLOSED", "fail_count": 0, "last_fail": null, "last_probe": null }
  }
}
```

## Reglas para agentes

1. **Al invocar un MCP**: verificar `task_state.mcp_status.<mcp>.state`
   - Si `CLOSED` → usar MCP normalmente
   - Si `OPEN` → usar fallback directamente, no intentar MCP
   - Si `HALF` → intentar MCP una vez; si falla → OPEN + fallback; si OK → CLOSED

2. **Al detectar fallo de MCP**:
   - Incrementar `fail_count`
   - Si `fail_count >= 2` → marcar `state: OPEN`, registrar `last_fail: <ISO timestamp>`
   - Registrar en session_log: `MCP_DEGRADED | mcp: <nombre> | fallback: <qué se usó> | fail_count: <N>`

3. **Probe (cada 5 minutos)**:
   - Si `state: OPEN` y han pasado ≥5 min desde `last_fail` → cambiar a `HALF`
   - En `HALF`: probar con 1 request simple (ej: `list_projects` para Supabase, `git status` para GitHub)
   - Si OK → `CLOSED`, resetear `fail_count: 0`
   - Si falla → `OPEN`, actualizar `last_fail`

4. **Propagación**: `mcp_status` viaja dentro de `task_state` en cada handoff entre agentes.

5. **Logging**: Toda transición de estado se registra en `session_log.md` y `session_spans.jsonl` con `event_type: MCP_CIRCUIT_CHANGE`.

## Ejemplo de flujo degradado

```
1. devops invoca mcp_io_github_git_create_pull_request → timeout 10s
2. fail_count: 1 (aún CLOSED)
3. devops reintenta → timeout 10s
4. fail_count: 2 → state: OPEN
5. devops usa fallback: `gh pr create --title "..." --body "..."`
6. Si `gh` no disponible: skip PR, reportar en summary: "PR skipped: GitHub MCP OPEN, gh CLI not available"
7. status: SUCCESS con nota: "commit+push OK, PR degraded"
8. 5 min después, siguiente ciclo: orchestrator ve mcp_status.github.state=OPEN
9. Han pasado ≥5 min → HALF → intenta mcp_io_github_git_get_repository
10. Si OK → CLOSED; si falla → OPEN de nuevo
```

## Notas de implementación

- El circuit breaker es **por sesión**, no persistente entre sesiones
- Si TODOS los MCPs están OPEN al inicio de un ciclo, el orchestrator debe advertir al usuario antes de continuar
- Un MCP en estado OPEN no bloquea tareas que no lo necesitan (ej: Supabase OPEN no bloquea una tarea de solo UI)
