# SISTEMA_COMPLETO — Especificación Operativa v3.1

Documento autoritativo de contratos, fases, reglas de verificación y evolución del sistema multi-agente.

---

## 1. Flujo de ejecución por fases

El sistema opera en modos clasificados por el `orchestrator` antes de planificar:

| Modo | Cuándo | Fases activas |
|---|---|---|
| CONSULTA | Pregunta o explicación | Ninguna — respuesta directa |
| RÁPIDO | <5 archivos, sin esquema, sin seguridad | Fase 2b + Fase 4 |
| COMPLETO | Todo lo demás | 0a → 0 → 1 → 2a → 2 → 3(paralelo) → 4 → 5 |

### Fases del MODO COMPLETO

```
Fase 0a  researcher    → research_brief + research_cache.json
Fase 0   analyst       → análisis estratégico (omitir si dominio conocido)
Fase 1   dbmanager     → migración SQL (omitir si sin cambio de esquema)
Fase 2a  tdd_enforcer  → tests en RED
Fase 2   backend|frontend|developer → implementación (pasar tests a GREEN)
Fase 3   auditor ∥ qa ∥ red_team   → verificación paralela
Fase 4   devops        → commit + push + PR (tras triple aprobación)
Fase 5a  session_logger  → audit trail (fire-and-forget)
Fase 5b  memory_curator  → curación parcial
```

---

## 2. TASK_STATE — Estado compartido

Todos los agentes propagan y actualizan el mismo objeto:

```json
{
  "task_id": "string",
  "goal": "string",
  "plan": [],
  "current_step": "string",
  "files": [],
  "risk_level": "LOW | MEDIUM | HIGH",
  "timeout_seconds": 0,
  "attempts": 0,
  "history": [],
  "constraints": [],
  "risks": [],
  "artifacts": []
}
```

Reglas:
- `history` siempre hace append, nunca sobreescribe.
- `timeout_seconds` define el presupuesto duro de cada fase (ver presupuestos en orchestrator).
- `risk_level` se clasifica en Fase 0c y condiciona qué verificadores son obligatorios.

---

## 3. Nivel de riesgo y verificadores requeridos

| risk_level | Verificadores en Fase 3 |
|---|---|
| LOW | ninguno (solo en MODO RÁPIDO) |
| MEDIUM | `auditor` + `qa` |
| HIGH | `auditor` + `qa` + `red_team` (obligatorio) |

---

## 4. Triple aprobación — Fase 3

Los tres agentes corren en paralelo con sufijos de task_id:

- `auditor` → `<task_id>.audit` → emite APROBADO / RECHAZADO
- `qa` → `<task_id>.qa` → emite CUMPLE / NO CUMPLE + `test_status`
- `red_team` → `<task_id>.redteam` → emite RESISTENTE / VULNERABLE

El `orchestrator` espera los tres `director_report` antes de habilitar Fase 4.

---

## 5. verified_digest — Integridad del payload

El `verified_digest` es un SHA-256 sobre el conjunto exacto de archivos verificados (`verified_files`). Se computa con `scripts/verified_digest.py`:

```bash
python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md
```

Reglas:
- Los tres agentes de Fase 3 deben recomputarlo independientemente y coincidir.
- `devops` recomputa antes del commit y rechaza si hay mismatch.
- `session_log.md` está excluido de `verified_files` y del digest.

---

## 6. Ciclo de verificación — verification_cycle

Formato: `<task_id_base>.r<retry_count>` o `<task_id_base>.override<N>.r<M>`.

- Identificador único por ciclo, nunca reutilizable en la misma sesión.
- Propagado explícitamente por el orchestrator a los tres agentes de Fase 3.
- `devops` rechaza cualquier bundle cuyo `verification_cycle` no derive del `task_id` base exacto de la invocación.

---

## 7. Regla de protección de contratos

Antes de modificar cualquier `agents/*.agent.md`:

1. `eval_runner` en `modo: "full"` → guardar como `PRE_CHANGE_SCORE`.
2. Aplicar el cambio.
3. `eval_runner` en `modo: "full"` → obtener `POST_CHANGE_SCORE`.
4. Si `POST_CHANGE_SCORE >= PRE_CHANGE_SCORE` y sin nuevos críticos → APROBADO.
5. Si no → revertir + escalar a human.

Hotfix: el usuario puede autorizar saltar con `APROBAR_SIN_EVAL` (uso único, ligado a `task_id`, `verification_cycle`, `branch_name`, artifacts y `verified_digest`).

---

## 8. Gestión de reintentos

- Máximo 2 reintentos (`retry_count < 2`).
- En cada reintento el orchestrator inyecta el `director_report` del agente que rechazó + `rejection_reason`.
- Si `retry_count >= 2` → `status: ESCALATE` + `escalate_to: human`.

---

## 9. Agentes y roles

| Agente | Rol | Permisos git |
|---|---|---|
| orchestrator | Planifica y coordina | No |
| researcher | Solo lectura + research_cache.json | No |
| analyst | Análisis estratégico | No |
| dbmanager | Diseño y migraciones | No |
| tdd_enforcer | Tests en RED | No |
| backend / frontend / developer | Implementación | No |
| auditor | Seguridad y correctitud | No |
| qa | Verificación funcional | No |
| red_team | Edge cases y vectores hostiles | No |
| devops | Commit + push + PR | **Sí — único agente autorizado** |
| session_logger | Audit trail append-only | No |
| memory_curator | Consolidación de aprendizajes | No |
| skill_installer | Detecta stack y skills | No |
| eval_runner | Evaluación del sistema | No |

---

## 10. Evals del sistema

El catálogo vive en `agents/evals/eval_catalog.md`. Modos disponibles:

- `full` — todas las evals (15–30 min); usar antes de PR o release.
- `grupo` — un grupo temático (routing, contratos, reintentos, memoria, coordinacion).
- `single` — una eval específica por ID.

Los reportes se guardan en `agents/eval_outputs/`.

---

## 11. MCP disponibles

- **GitHub** (`mcp_io_github_git_*`) — operaciones de repositorio, incluyendo `mcp_io_github_git_create_pull_request` para PR.
- **Supabase** (`mcp_com_supabase__*`) — base de datos y edge functions.
- **Vercel** (`mcp_vercel_*`) — despliegue y logs.
- **Filesystem** — lectura/escritura local según `.mcp.json`.

---

## 12. Evolución del sistema

Los cambios al sistema siguen el flujo:

1. Propuesta documentada en `session_log.md`.
2. Baseline pre-change con `eval_runner modo: "full"`.
3. Implementación delegada al agente correspondiente.
4. Triple aprobación Fase 3 + eval post-change.
5. `devops` aplica el commit con PR documentado.
6. `memory_curator` consolida aprendizajes.
