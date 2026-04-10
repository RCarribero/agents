# Sistema Multi-Agente — Documentación Completa

**Versión:** v3.1.1
**Fecha:** 2026-04-10
**Stack activo:** workspace local de orquestación multi-agente y toolkit operativo. Las tareas frontend pueden apuntar a repos externos Flutter/Dart + Riverpod cuando el proyecto activo tenga `pubspec.yaml`.

---

## 1. Flujo de ejecución

### MODO CONSULTA

```
Usuario
  └─► orchestrator (respuesta directa)
                   └─► [opcional] researcher (si hace falta contexto)
```

### MODO RÁPIDO

```
Usuario
  └─► orchestrator
        └─► [Fase 2b] backend | frontend | developer
                               └─► [Fase 4] devops
                                             └─► session_logger
```

### MODO COMPLETO

```
Usuario
  └─► orchestrator
        │
        ├─► [Fase -1] skill_installer  →  skill_context (nunca bloquea)
        │
        ├─► [Fase 0a] researcher  →  research_brief
        ├─► [Fase 0]  analyst     →  análisis estratégico (si aplica)
        │
        ├─► [Fase 1]  dbmanager   →  diseño/migraciones (solo si hay cambio de datos)
        ├─► [Fase 2a] tdd_enforcer → tests en RED (si aplica)
        ├─► [Fase 2]  backend | frontend | developer
        │
        ├─► [Fase 3 — PARALELO]
        │         auditor (.audit)   qa (.qa)   red_team (.redteam)
        │         SI los 3 ──► orchestrator valida verified_digest → Fase 4
        │         NO alguno ──► retry_count++ → re-invocar implementador
        │                       retry_count ≥ 2 ──► ESCALATE → human
        │
        ├─► [Fase 4] devops  (triple aprobación + verified_digest)
        │
        └─► [Fase 5] session_logger + memory_curator (parcial)

Al cierre de sesión: memory_curator (completo)
```

### Rutas de retry y escalación

```
Implementador falla ──► auditor | qa | red_team rechazan
  └─► orchestrator adjunta report(s) de rechazo → re-invoca implementador
      retry_count = 1 ──► 2do intento
      retry_count = 2 ──► ESCALATE → human (historial completo adjunto)

override humano ──► nuevo verification_cycle: <task_id>.override<N>.r0
                    EVAL_TRIGGER fresco requerido si toca .agent.md
```

---

## 2. Clasificador de complejidad

| Señal | MODO CONSULTA | MODO RÁPIDO | MODO COMPLETO |
|---|---|---|---|
| Tipo de tarea | pregunta, explicación | cambio puntual y acotado | feature nueva, múltiples archivos |
| Código nuevo | no | mínimo | sí, con dependencias |
| Cambio de esquema DB | no | no | sí |
| Tests requeridos | no | no o pocos | sí |
| Riesgo de regresión | ninguno | bajo | medio-alto |

**Escalación de RÁPIDO a COMPLETO:** el implementador emite `status: ESCALATE` si detecta que el cambio es más complejo de lo esperado.

**Señales de clasificación:**
- BUGFIX: "falla", "bug", "error", "rompe", "no funciona"
- CONSULTA: "buscar", "consultar", "listar", "filtrar", "obtener"
- SCHEMA_CHANGE: "añadir campo", "nueva tabla", "migración", "columna", "RLS"

---

## 3. Agentes

### Agentes invocables por el usuario

| Agente | Rol | Cuándo entra |
|---|---|---|
| `orchestrator` | Clasifica, planifica y coordina | Siempre |
| `analyst` | Análisis estratégico | Fase 0 cuando el dominio es desconocido |
| `eval_runner` | Evalúa contratos y reglas del sistema | Gate de evaluación o revisión manual |

### Agentes internos del flujo

| Agente | Rol | Fase típica |
|---|---|---|
| `skill_installer` | Detecta stack y skills | Fase -1 |
| `researcher` | Mapea módulo y riesgos | Fase 0a |
| `dbmanager` | Diseña datos y migraciones | Fase 1 |
| `tdd_enforcer` | Escribe tests en RED | Fase 2a |
| `backend` | Implementación server-side o lógica de integración | Fase 2 |
| `frontend` | Implementación UI/UX | Fase 2 |
| `developer` | Implementación genérica | Fase 2 |
| `auditor` | Seguridad y correctitud crítica | Fase 3 |
| `qa` | Verificación funcional | Fase 3 |
| `red_team` | Casos hostiles y asunciones rotas | Fase 3 |
| `devops` | Commit, push y PR cuando aplica | Fase 4 |
| `session_logger` | Audit trail append-only | Fase 5a |
| `memory_curator` | Curación de aprendizajes | Fase 5b y cierre |

**Convenciones clave del sistema:**
- `TASK_STATE` es el estado compartido del ciclo.
- El flujo de verificación exige consenso de `verified_digest`.
- `session_log.md` queda fuera de `verified_files` y del digest.
- El repo no depende de un servicio HTTP embebido para enriquecer contexto o registrar eventos.

---

## 4. TASK_STATE

Core mínimo obligatorio:

```json
{
  "task_id": "",
  "goal": "",
  "plan": [],
  "current_step": "",
  "files": [],
  "risk_level": "LOW | MEDIUM | HIGH",
  "timeout_seconds": 0,
  "attempts": 0,
  "history": []
}
```

Campos extendidos del proyecto:

- `constraints`
- `risks`
- `artifacts`

Reglas:

- `history` siempre hace append.
- `attempts` se sincroniza con `retry_count`.
- `timeout_seconds` se fija por fase.
- `files` define el scope exacto del ciclo.

---

## 5. Instrucciones del sistema

### `global.instructions.md`

- Leer `agents/memoria_global.md` y `AUTONOMOUS_LEARNINGS` antes de actuar.
- Leer `stack.md` del proyecto; si no existe, invocar `skill_installer`.
- Cerrar siempre con `<director_report>` y `<agent_report>`.
- Dos fallos en la misma tarea implican `ESCALATE` a `human`.

### `readonly.instructions.md`

- Aplica a `eval_runner`, `auditor`, `qa`, `red_team`, `researcher`, `session_logger`.
- Prohíbe escritura de código, operaciones git y comandos que modifiquen archivos.
- Permite comandos de lectura y verificación.

### `git.instructions.md`

- Aplica solo a `devops`.
- Exige triple aprobación y validación de branch antes de operar con git.
- Obliga a Conventional Commits y trailer `Co-authored-by: Copilot`.

### `stack-override.instructions.md`

- Si existe `overrides.md` o `.copilot/overrides.md`, se lee antes de actuar.
- El override tiene precedencia en arquitectura, lint/build/test y convenciones.
- No puede anular restricciones de `readonly.instructions.md`.

---

## 6. Scripts de validación y soporte

### `validate-agents.sh`

Verifica integridad estructural de cada `.agent.md` en `agents/`.

```bash
./scripts/validate-agents/validate-agents.sh [ruta/a/agents/]
```

Chequea frontmatter, bloques de report, presencia de `AUTONOMOUS_LEARNINGS` y consistencia contractual básica.

### `validate-stack.sh`

Detecta el stack del proyecto y crea `stack.md` en la raíz si no existe.

```bash
./scripts/validate-stack/validate-stack.sh [ruta/proyecto/]
```

Soporta detección de stacks comunes de proyectos objetivo y no sobreescribe `stack.md` si ya está curado manualmente.

### `validate-memory.sh`

Valida el estado de la memoria en tres dimensiones.

```bash
./scripts/validate-memory/validate-memory.sh [ruta/agents/] [ruta/session_log.md]
```

### `token-report.sh`

Estima el tamaño en tokens de cada `.agent.md`.

```bash
./scripts/token-report/token-report.sh [ruta/agents/]
```

### `run-tests.sh`

Ejecuta los tests detectando el stack automáticamente.

En la raíz de este toolkit, el stack detectado es `toolkit` y el script ejecuta `run_eval_gate.py` en modo sin reporte persistente para que `tests` funcione también en sandbox read-only.

```bash
./scripts/run-tests/run-tests.sh [PROJECT_ROOT] [--json]
```

### `run-lint.sh`

Ejecuta el linter detectando el stack automáticamente.

En la raíz de este toolkit, el stack detectado es `toolkit` y el script ejecuta `validate-agents.sh` seguido de `token-report.sh` para alinear `/lint` con los checks estructurales del repositorio.

```bash
./scripts/run-lint/run-lint.sh [PROJECT_ROOT] [--json]
```

### `sandbox-run.sh`

Orquesta tests o lint en un contenedor Docker aislado.

```bash
./scripts/sandbox-run/sandbox-run.sh <project_root> <tests|lint> [--json]
```

### `run_eval_gate.py`

Ejecuta checks automáticos sobre contratos de agentes y genera un reporte markdown.

```bash
python scripts/run_eval_gate.py --root . --report-file agents/eval_outputs/ci_eval_gate_report.md
```

### `verified_digest.py`

Calcula y verifica el `verified_digest` usado por Fase 3 y Fase 4.

```bash
python scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md
```

---

## 7. MCP servers

Configuración en `.mcp.json` (versión 1.0):

### `filesystem`

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-filesystem ${workspaceFolder}` |
| Agentes con acceso | orchestrator, researcher, auditor, backend, dbmanager, skill_installer |

Permite leer y navegar el workspace sin depender solo de `context.files`.

### `github`

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-github` |
| Env requerida | `GITHUB_TOKEN` |
| Agentes con acceso | devops |

### `postgres`

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-postgres ${env:POSTGRES_DB_URL}` |
| Env requerida | `POSTGRES_DB_URL` |
| Agentes con acceso | backend, dbmanager |

Uso previsto: proyectos activos que realmente necesiten queries directas o migraciones en Postgres.

---

## 8. Sistema de memoria

### Ciclo completo

```
1. LECTURA (inicio de cada agente)
   └─► Lee memoria_global.md + AUTONOMOUS_LEARNINGS propio

2. ESCRITURA durante ciclo
   └─► session_logger → session_log.md (append-only)

3. CURACIÓN PARCIAL (Fase 5b, post-devops)
   └─► memory_curator extrae lecciones del ciclo → AUTONOMOUS_LEARNINGS

4. CURACIÓN COMPLETA (cierre de sesión)
   └─► memory_curator actualiza memoria_global.md
```

### Límites del sistema

| Recurso | Límite | Acción si se supera |
|---|---|---|
| AUTONOMOUS_LEARNINGS por agente | 10 notas | memory_curator archiva las más antiguas |
| session_log.md | 500 líneas | validate-memory.sh emite WARN |

---

## 9. Session log

Formato de entrada:

```
[YYYY-MM-DD HH:MM] EVENT_TYPE | task: <task_id> | <from> → <to> | status: <s> | artifacts: [<lista>] | <notes>
```

Eventos habituales: `AGENT_TRANSITION`, `EVAL_TRIGGER`, `PHASE_COMPLETE`, `ERROR`, `ESCALATION`.

`session_log.md` es `audit_trail_artifact` y queda excluido de `verified_files` y de la computación del digest.

---

## 10. Arquitectura de archivos

```text
.
├── .github/
│   ├── copilot-instructions.md
│   ├── prompts/
│   │   ├── start.prompt.md
│   │   ├── validar.prompt.md
│   │   ├── tests.prompt.md
│   │   ├── lint.prompt.md
│   │   ├── sandbox-tests.prompt.md
│   │   ├── sandbox-lint.prompt.md
│   │   ├── eval-gate.prompt.md
│   │   └── dockerize.prompt.md
│   └── workflows/
│       ├── ci.yml
│       └── rollback.yml
├── .mcp.json
├── agents/
│   ├── *.agent.md
│   ├── evals/
│   ├── eval_outputs/
│   └── memoria_global.md
├── instructions/
├── scripts/
│   ├── Dockerfile.sandbox
│   ├── run-lint/
│   ├── run-tests/
│   ├── sandbox-run/
│   ├── start/
│   ├── token-report/
│   ├── validate-agents/
│   ├── validate-memory/
│   ├── validate-stack/
│   ├── install-copilot-layout/
│   ├── install-repo-layout/
│   ├── docker-launcher/
│   ├── run_eval_gate.py
│   └── verified_digest.py
├── session_log.md
├── stack.md
└── SISTEMA_COMPLETO.md
```

---

## 11. Eval system

El repositorio mantiene un catálogo de evaluaciones en `agents/evals/` y reportes generados en `agents/eval_outputs/`.

Objetivos del sistema de evals:

- validar routing y contratos de agentes
- detectar drift entre reglas y documentación
- generar un baseline reproducible antes de tocar contratos críticos
- dar soporte al CI mediante `run_eval_gate.py`

Limitación conocida: no todos los casos se ejecutan end-to-end; parte del catálogo sigue dependiendo de simulación contractual o inspección estructural.

---

## 12. Historial de versiones

| Versión | Fecha | Cambios principales |
|---|---|---|
| v1.0.0 | 2026-04-07 | Sistema base: orchestrator, backend, frontend, developer, auditor, qa, devops, session_logger, memory_curator |
| v1.0.1 | 2026-04-07 | Fix routing para dbmanager |
| v2.0.0 | 2026-04-07 | Añadido: red_team, tdd_enforcer, researcher, skill_installer, analyst |
| v2.1.0 | 2026-04-09 | verified_digest canónico; validación de branch; instructions y scripts de validación |
| v2.1.x | 2026-04-09 | verification_cycle irrepetible; igualdad exacta de `verified_files`; consensus digest; index binding en devops |
| v3.1.0 | 2026-04-09 | Toolkit MCP, sandbox Docker, copilot-instructions y contratos v3.1 |
| v3.1.1 | 2026-04-10 | Eliminada la API embebida del workspace; limpieza de wiring, docs, CI y tooling asociado |

---

## 13. Guía de inicio rápido

1. **Clona el repositorio** y abre la raíz del proyecto en VS Code.
2. **Bootstrap inicial opcional** con `/start` o `./scripts/start/start.ps1 .` para generar `stack.md` y preparar el repo actual.
3. **Crea `.env`** en la raíz si tu flujo necesita variables locales. Variables típicas:
   ```
   POSTGRES_DB_URL=postgresql://...
   GITHUB_TOKEN=tu-github-pat
   OPENAI_API_KEY=sk-...
   ```
4. **Detecta el stack** de tu proyecto:
   ```bash
   ./scripts/validate-stack/validate-stack.sh /ruta/a/tu/proyecto
   ```
5. **Verifica la integridad del sistema:**
   ```bash
   ./scripts/validate-agents/validate-agents.sh
   ./scripts/validate-memory/validate-memory.sh
   ./scripts/token-report/token-report.sh
   ```
6. **Envía tu primera tarea:**
   ```
   @orchestrator Implementa [tu tarea aquí]
   ```
7. **Valida el resultado** con tests, lint y eval gate si tocaste contratos.
   En la raíz de este toolkit, `tests` equivale a eval gate sin reporte persistente y `lint` equivale a `validate-agents` + `token-report`.
8. **Al cerrar la sesión**, invoca `memory_curator` (modo completo) si el flujo operativo lo requiere.

---

*Generado automáticamente el 2026-04-10 por GitHub Copilot.*
