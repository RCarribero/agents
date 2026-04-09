# Sistema Multi-Agente — Documentación Completa

**Versión:** v3.1.0
**Fecha:** 2026-04-09
**Stack activo:** workspace local de orquestación multi-agente + Agents API (FastAPI + Python 3.11 + Supabase). Las tareas frontend pueden apuntar a repos externos Flutter/Dart + Riverpod cuando el proyecto activo tenga `pubspec.yaml`.

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

### MODO COMPLETO (flujo estándar)

```
Usuario
  └─► orchestrator (lee memoria + RAG retrieve_context)
        │
        ├─► [Fase -1] skill_installer  →  skill_context (nunca bloquea)
        │
        ├─► [Fase 0a] researcher  →  research_brief
        │
        ├─► [Fase 0]  analyst  (solo si dominio desconocido)
        │
        ├─► [Fase 1]  dbmanager  (solo si cambio de esquema DB)
        │
        ├─► [Fase 2a] tdd_enforcer  →  tests en RED
        │
        ├─► [Fase 2]  backend | frontend | developer  →  implementación
        │
        ├─► [Fase 3 — PARALELO]
        │         auditor (.audit)   qa (.qa)   red_team (.redteam)
        │         SI los 3 ──► orchestrator valida verified_digest → Fase 4
        │         NO alguno ──► retry_count++ → re-invocar implementador
        │                       retry_count ≥ 2 ──► ESCALATE → human
        │
        ├─► [Fase 4]  devops  (triple aprobación + verified_digest)
        │              └─► [Opcional] MCP GitHub → create_pull_request
        │
        └─► [Fase 5]  session_logger  +  memory_curator (parcial)

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
| Código nuevo | no | mínimo (1-2 archivos) | sí, con dependencias |
| Cambio de esquema DB | no | no | sí |
| Tests requeridos | no | no/pocos | sí (TDD) |
| Riesgo de regresión | ninguno | bajo | medio-alto |

**Escalación de RÁPIDO a COMPLETO:** el implementador emite `status: ESCALATE` si detecta que el cambio es más complejo de lo esperado.

**Señales de clasificación:**
- BUGFIX: "falla", "bug", "error", "rompe", "no funciona"
- CONSULTA: "buscar", "consultar", "listar", "filtrar", "obtener"
- SCHEMA_CHANGE: "añadir campo", "nueva tabla", "migración", "columna", "RLS"

---

## 3. Agentes

### Agentes invocables por el usuario

---

#### orchestrator

| Campo | Valor |
|---|---|
| Modelo | GPT-5.4 |
| user-invocable | sí |
| Temperatura | por defecto |

**Rol:** Director de orquesta. Planifica y delega. Nunca implementa.

**Cuándo se invoca:** Siempre — es el punto de entrada de toda tarea del usuario.

**Reglas clave:**
- Nunca implementa — delega siempre en modos de ejecución
- **Rule 0c (v3.1):** Inicializa `TASK_STATE` y clasifica `risk_level` (LOW/MEDIUM/HIGH) antes de crear el plan
- Propaga `risk_level` y snapshot de `TASK_STATE` en el contrato de entrada de cada sub-agente
- **Core de `TASK_STATE`:** `task_id`, `goal`, `plan`, `current_step`, `files`, `risk_level`, `attempts`, `history`. El proyecto añade `constraints`, `risks` y `artifacts` como extensiones compatibles.
- Tabla de routing de verificadores según `risk_level`: LOW→ninguno (MODO RÁPIDO), MEDIUM→`auditor`+`qa`, HIGH→`auditor`+`qa`+`red_team`
- En Fase 3 define `verification_cycle: <task_id>.r<retry_count>` y propaga `branch_name` a los tres verificadores
- Valida que `verified_digest` sea idéntico en los tres reports antes de habilitar Fase 4
- Override humano abre nuevo ciclo con `verification_cycle: <task_id>.override<N>.r0`
- `session_log.md` es `audit_trail_artifact` — excluido de `verified_files` y del digest
- Invoca RAG (`retrieve_context` k=5) antes de planificar si la API está disponible
- **Salida dual (v3.1):** emite AMBOS `<director_report>` (control legacy) y `<agent_report>` (nuevo, incluye `goal`, `current_step`, `files`, `attempts`, `issues` y `task_state` JSON actualizado)

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### analyst

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | 0.7 |
| user-invocable | sí |

**Rol:** Analista estratégico. Detecta features ausentes y genera ideas accionables.

**Cuándo se invoca:** Fase 0 del MODO COMPLETO cuando el dominio es desconocido o hay deuda técnica.

**Reglas clave:**
- Lee `memoria_global.md` antes de analizar — no repite ideas ya documentadas
- Clasifica ideas en 4 categorías: Arquitectura, Rendimiento, Producto, Features ausentes
- Máximo 10 ideas por sesión, priorizadas por ratio impacto/esfuerzo
- Solo sugiere con evidencia real del código — no inventa gaps

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### eval_runner

| Campo | Valor |
|---|---|
| Modelo | GPT-5.4 |
| user-invocable | sí |
| Temperatura | por defecto |

**Rol:** Evaluador del sistema. Mide si los agentes cumplen sus contratos. Solo observa.

**Cuándo se invoca:** Gate de evaluación (antes de Fase 4) o manualmente para health checks.

**Reglas clave:**
- NUNCA modifica `.agent.md`, `memoria_global.md` ni `AUTONOMOUS_LEARNINGS`
- Cada eval corre en contexto limpio — sin reutilizar estado
- Timeout de 5 minutos por eval; si supera → FAIL automático
- Guarda outputs en `agents/eval_outputs/eval-NNN_v{version}_{fecha}.json`
- Si infraestructura insuficiente → `PARTIAL` con razón `infraestructura_pendiente`

**AUTONOMOUS_LEARNINGS:** *(solo lectura)*

---

### Agentes internos (por orden de aparición en el flujo)

---

#### skill_installer

| Campo | Valor |
|---|---|
| Modelo | Claude Haiku 4.5 |
| Temperatura | 0.0 |
| user-invocable | no |

**Rol:** Detecta el stack y construye el `skill_context`. Primera acción de cada sesión.

**Cuándo se invoca:** Fase -1, siempre antes de cualquier otro agente.

**Reglas clave:**
- Verifica cache en `skills_cache.md` (válido 24 horas)
- Detecta stack desde `.copilot/stack.md`, luego manifests (`pubspec.yaml`, `package.json`, `requirements.txt`, `go.mod`)
- Nunca bloquea el flujo — cualquier error devuelve `status: SKIPPED`
- Registra `autoskills: unavailable` si la herramienta no está disponible

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### researcher

| Campo | Valor |
|---|---|
| Modelo | Claude Opus 4.6 |
| Temperatura | 0.3 |
| user-invocable | no |

**Rol:** Investigación de solo lectura. Mapea el módulo afectado y produce un `research_brief`.

**Cuándo se invoca:** Fase 0a del MODO COMPLETO, siempre que haya código existente afectado.

**Reglas clave:**
- Solo lectura — nunca crea ni modifica archivos
- Llama `retrieve_context` (k=5) vía MCP si `AGENTS_API_URL` disponible
- Usa `read_file` del MCP filesystem server si disponible
- Si riesgo alto → coloca `next_agent: analyst` en el informe

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### dbmanager

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** Arquitecto de datos. Diseña, migra y protege el esquema.

**Cuándo se invoca:** Fase 1, solo cuando hay cambio estructural de esquema (CREATE TABLE, ALTER TABLE, nueva RLS, índice nuevo).

**Reglas clave:**
- Migraciones en la ruta de migraciones del proyecto activo; en este workspace `agents/api/migrations/*.sql` — siempre idempotentes y backward-compatible
- 3NF por defecto + RLS obligatoria con `ENABLE ROW LEVEL SECURITY`
- Estrategia segura: `add → backfill → migrate → cleanup`
- Nunca borrar columnas en caliente
- PK: `id` (BIGINT o UUIDv4), FK con `ON DELETE` explícito, campos `created_at`/`updated_at`

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### tdd_enforcer

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | 0.0 |
| user-invocable | no |

**Rol:** Guardián del TDD. Escribe tests que fallen (RED) antes de que el implementador actúe.

**Cuándo se invoca:** Fase 2a, siempre que aplique lógica nueva.

**Reglas clave:**
- Solo escribe tests — nunca toca código de producción
- Tests deben compilar sin errores de sintaxis pero fallar en ejecución (RED válido)
- Cubre: happy path + caso de error + validación fallida
- Si tests ya están en GREEN → `status: ESCALATE` con `escalate_to: human`

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### developer

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** Implementador genérico. Hace pasar los tests de RED a GREEN.

**Cuándo se invoca:** Fase 2, cuando la tarea no es específicamente frontend o backend puro.

**Reglas clave:**
- Lee el motivo de rechazo antes de modificar código en reintentos
- No modifica tests — si parecen incorrectos, escala
- Archivos nuevos en la ruta real del proyecto activo; `lib/features/<feature>/` o `lib/shared/` solo cuando el proyecto sea Flutter/Dart
- No introduce dependencias externas sin listarlas en el report
- Escala a human tras dos iteraciones fallidas
- **Entrada v3.1:** recibe `risk_level` y `task_state` del orchestrator; propaga en salida vía `<agent_report>`

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### backend

| Campo | Valor |
|---|---|
| Modelo | Haiku |
| Temperatura | 0.0 |
| user-invocable | no |

**Rol:** Desarrollador backend. Implementa lógica de API, servicios y persistencia.

**Cuándo se invoca:** Fase 2, en tareas de API / backend / lógica de servidor.

**Reglas clave:**
- Ejecuta análisis estático antes de entregar; si `sandbox-run.sh` disponible → `lint --json`, `exit_code=0`
- Si `tdd_status: RED`: ejecuta `sandbox-run.sh tests --json` y deriva `test_status` del `exit_code`
- Sin números ni cadenas mágicas — extrae constantes nombradas
- Escala a human tras dos iteraciones fallidas
- **Entrada v3.1:** recibe `risk_level` y `task_state` del orchestrator; propaga en salida vía `<agent_report>`

**AUTONOMOUS_LEARNINGS (actuales):**
```
- Validar input de búsqueda con parámetros, nunca concatenar strings en queries dinámicas.
- Paginación por cursor (id > last_seen) preferible a OFFSET en tablas grandes.
- En PATCH de tarea con usuarios_ids, mantener validación estricta de membresía por proyecto.
- Al mover una tarea fuera de `terminado`, recalcular `completada` desde la columna destino.
- En transiciones terminado<->no-terminado, centralizar una única regla de derivación.
```

---

#### frontend

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** Desarrollador frontend. Implementa componentes, pantallas y flujos de usuario.

**Cuándo se invoca:** Fase 2, en tareas de UI/UX/componentes.

**Reglas clave:**
- Cero estilos inline — usa el sistema de estilos del proyecto (Tailwind, CSS Modules, ThemeData)
- Accesibilidad no es opcional: roles ARIA, teclado, contraste WCAG AA (ratio ≥4.5:1)
- Responsivo por defecto — mobile y desktop
- No inventa lógica de negocio — escala si la UI necesita datos no definidos
- Componentes pequeños y reutilizables; si generalizable → `shared/` o `components/`
- **Entrada v3.1:** recibe `risk_level` y `task_state` del orchestrator; propaga en salida vía `<agent_report>`

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### auditor

| Campo | Valor |
|---|---|
| Modelo | Sonnet |
| Temperatura | 0.0 |
| user-invocable | no |

**Rol:** Auditor de seguridad. Veredicto binario: APROBADO o RECHAZADO.

**Cuándo se invoca:** Fase 3, en paralelo con `qa` y `red_team`.

**Reglas clave:**
- Recomputa `verified_digest` de forma independiente (SHA-256 por archivo → concatenación alfabética → SHA-256 final)
- Busca: inyección SQL/NoSQL, XSS, secretos hardcodeados, bypass de RLS, race conditions, dependencias vulnerables
- Usa MCP filesystem (`read_file`) si disponible
- Llama `log_agent_event` tras emitir veredicto (fire-and-forget)
- No opina sobre estilo — solo seguridad y correctitud crítica

**Contrato de salida (sufijo `.audit`):** `veredicto` APROBADO|RECHAZADO, `verification_cycle`, `branch_name`, `verified_files`, `verified_digest`, `rejection_reason` si aplica.
- **Entrada v3.1:** recibe `risk_level` (propagado por orchestrator); lo incluye en `<agent_report>` de salida

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### qa

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** QA funcional. Verifica que el código hace lo pedido. Veredicto: CUMPLE o NO CUMPLE.

**Cuándo se invoca:** Fase 3, en paralelo con `auditor` y `red_team`.

**Reglas clave:**
- Recomputa `verified_digest` de forma independiente (mismo algoritmo que auditor)
- Solo actúa si `previous_output` contiene `status: SUCCESS` del implementador
- Si `sandbox-run.sh` disponible → `tests --json`; deriva `test_status` del `exit_code`
- `test_status` explícito: `GREEN` | `FAILED` | `NOT_APPLICABLE`

**Contrato de salida (sufijo `.qa`):** `veredicto` CUMPLE|NO CUMPLE, `test_status`, `verification_cycle`, `branch_name`, `verified_files`, `verified_digest`.
- **Entrada v3.1:** recibe `risk_level` (propagado por orchestrator); lo incluye en `<agent_report>` de salida

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### red_team

| Campo | Valor |
|---|---|
| Modelo | GPT-5.4 |
| Temperatura | 0.5 |
| user-invocable | no |

**Rol:** Atacante. Busca inputs maliciosos, edge cases y asunciones rotas. Veredicto: RESISTENTE o VULNERABLE.

**Cuándo se invoca:** Fase 3, en paralelo con `auditor` y `qa`.

**Reglas clave:**
- Recomputa `verified_digest` de forma independiente (mismo algoritmo)
- Nunca modifica código — solo ataca e informa
- Busca: race conditions de negocio, bypass de validaciones, asunciones rotas, edge cases numéricos/vacíos/nulos
- Report siempre al orchestrator — NUNCA habilita Fase 4 directamente

**Contrato de salida (sufijo `.redteam`):** `veredicto` RESISTENTE|VULNERABLE, `vulnerabilities`, `verification_cycle`, `branch_name`, `verified_files`, `verified_digest`.
- **Entrada v3.1:** recibe `risk_level`; HIGH garantiza invocación obligatoria de `red_team`; lo incluye en `<agent_report>` de salida

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### devops

| Campo | Valor |
|---|---|
| Modelo | Claude Sonnet 4.6 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** Responsable de despliegue y control de versiones. Único agente con permisos git.

**Cuándo se invoca:** Fase 4, solo con triple aprobación + `test_status GREEN/NOT_APPLICABLE` + `verified_digest` consensuado.

**Reglas clave:**
- Ejecuta VERIFICACIÓN DE BRANCH OBLIGATORIA como primera acción (5 pasos: `rev-parse`, `status --porcelain`, `log -1`, `ls-remote`, `pull --rebase`)
- Valida igualdad exacta: `context.files == context.verified_files == bundle.verified_files`
- Recalcula `verified_digest` sobre el working tree antes del commit
- Staging limpio: `reset índice + git add` solo de archivos en `verified_files`
- Conventional Commits + trailer `Co-authored-by: Copilot`
- Tras push: `create_pull_request` con `task_id`, `verification_cycle`, `verified_digest`
- Rechaza cualquier bundle de ciclo anterior (anti-replay)

**AUTONOMOUS_LEARNINGS:**
```
- Migraciones de DB deben ir en commit separado (feat(db):) antes del commit de lógica.
- Commits de features completas (DB+backend+frontend) deben dividirse en 3 commits atómicos.
```

---

#### session_logger

| Campo | Valor |
|---|---|
| Modelo | Claude Haiku 4.5 |
| Temperatura | 0.0 |
| user-invocable | no |

**Rol:** Registrador append-only de transiciones en `session_log.md`.

**Cuándo se invoca:** Fase 5a, tras cada transición relevante + EVAL_TRIGGER + ESCALATION.

**Reglas clave:**
- Append-only — nunca sobreescribe `session_log.md`
- Formato: `[YYYY-MM-DD HH:MM] EVENT_TYPE | task: <id> | <from> → <to> | status: <s> | artifacts: [<lista>] | <notes>`
- Si falla → `status: SKIPPED`, no propaga el error

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

#### memory_curator

| Campo | Valor |
|---|---|
| Modelo | GPT-5.4 |
| Temperatura | por defecto |
| user-invocable | no |

**Rol:** Curador de memoria. Extrae lecciones y actualiza `memoria_global.md` y `AUTONOMOUS_LEARNINGS`.

**Cuándo se invoca:** Fase 5b (parcial, post-devops) y al cierre de sesión (completo).

**Modos:**
- **Parcial:** Extrae lecciones del ciclo recién completado, escribe en `AUTONOMOUS_LEARNINGS`. Si agente supera 10 notas → archiva las más antiguas.
- **Completo:** Lee historial completo y actualiza `memoria_global.md` con entradas `## [YYYY-MM-DD] <id>`.

**AUTONOMOUS_LEARNINGS:** *(sin notas curadas todavía)*

---

## 4. Skills

Detectados automáticamente por `skill_installer` en Fase -1. Almacenados en `skills_cache.md`.

| Skill | Descripción | Stacks |
|---|---|---|
| flutter-ui-ux | UI/UX Flutter con animaciones y responsive | Flutter/Dart |
| supabase | CLI Supabase, migraciones, RLS, Edge Functions | cualquier + Supabase |
| supabase-nextjs | Next.js con Supabase y Drizzle ORM | Next.js + Supabase |
| i18n-expert | Internacionalización React/TS con i18next | React/TypeScript |
| i18n-localization | Detección de strings hardcodeados, locales, RTL | multi-stack |
| code-to-music | Generación de música con código (output .mp3) | Python/Node.js |
| tonejs | Síntesis de audio en browser con Web Audio API | JavaScript |
| find-skills | Descubrir e instalar skills disponibles | meta-skill |
| lottie-animations | Animaciones After Effects en web/React | React/Next.js |
| voice-note-to-midi | Convertir audio a MIDI con detección de pitch | Python |
| agent-customization | Crear/editar archivos de customización VS Code | meta-skill |

---

## 5. Instruction files

### global.instructions.md

**Aplica a:** todos los agentes (`applyTo: "**"`)

- Leer `agents/memoria_global.md` y `AUTONOMOUS_LEARNINGS` del propio agente antes de actuar
- Leer `stack.md` del proyecto; si no existe, invocar `skill_installer`
- Cerrar siempre con `<director_report>` completo — nunca omitir `next_agent`
- **v3.1:** Cerrar también con `<agent_report>` (salida dual obligatoria con core de shared state)
- 2 fallos en la misma tarea → `status: ESCALATE` con `escalate_to: human`
- No ejecutar acciones fuera del rol propio

---

### readonly.instructions.md

**Aplica a:** `eval_runner`, `auditor`, `qa`, `red_team`, `researcher`, `session_logger`

- NO crear, modificar ni eliminar archivos de código ni contratos de agente
- NO ejecutar comandos que escriban en disco (`>`, `tee`, `write`, etc.)
- NO realizar ninguna operación git (`add`, `commit`, `push`, `pull`, `checkout`)
- SÍ ejecutar comandos de lectura/verificación: `flutter test`, `flutter analyze`, `pytest`
- Incumplimiento → `status: ESCALATE` con `escalate_to: human`

---

### git.instructions.md

**Aplica a:** `devops` únicamente

- `devops` es el único agente con permisos git
- Triple aprobación requerida antes de cualquier operación git
- Ejecutar VERIFICACIÓN DE BRANCH OBLIGATORIA como primera acción
- Conventional Commits obligatorios con trailer `Co-authored-by: Copilot`
- Push siempre a `context.branch_name` explícito — nunca asumir `main`
- Incumplimiento → `status: REJECTED`

---

### stack-override.instructions.md

**Aplica a:** todos los agentes (`applyTo: "**"`)

- Si existe `.copilot/overrides.md` en el proyecto → leerlo antes de actuar
- Override tiene precedencia en: convenciones de proyecto, build/test/lint, arquitectura
- Excepción: `readonly.instructions.md` NO puede ser anulada por ningún override
- Documentar en `summary` del `director_report` qué override se aplicó
- Si no existe `.copilot/overrides.md` → continuar sin interrumpir

---

## 6. Prompt templates

*(No se encontraron archivos en `.github/prompts/`. Sección omitida.)*

---

## 7. Validation scripts

### validate-agents.sh

Verifica integridad estructural de cada `.agent.md` en `agents/`.

```bash
./scripts/validate-agents.sh [ruta/a/agents/]
```

Verifica: frontmatter con `name` y `description`, bloque `<director_report>`, sección `AUTONOMOUS_LEARNINGS`.
Output: `OK <agente>` o `FAIL <agente> → <motivo>`. Exit 1 si hay algún FAIL.

---

### validate-stack.sh

Detecta el stack del proyecto y crea `.copilot/stack.md` si no existe.

```bash
./scripts/validate-stack.sh [ruta/proyecto/]
```

Detecta: flutter, node, nextjs, react, python, fastapi, go, rust.
Si ya existe `stack.md` → lo muestra sin sobreescribir.

---

### validate-memory.sh

Valida el estado de la memoria en tres dimensiones.

```bash
./scripts/validate-memory.sh [ruta/agents/] [ruta/session_log.md]
```

- `[1/3] memoria_global.md` → OK | WARN (sin entradas) | FAIL (no existe)
- `[2/3] AUTONOMOUS_LEARNINGS` → OK | WARN (supera 10) | INFO (0 notas)
- `[3/3] session_log.md` → OK | WARN (supera 500 líneas — archivar)

---

### token-report.sh

Estima el tamaño en tokens de cada `.agent.md` (chars / 4).

```bash
./scripts/token-report.sh [ruta/agents/]
```

Tabla: Agente | Tokens est. | Estado. WARN si supera 2000 tokens.

---

### run-tests.sh

Ejecuta los tests detectando el stack automáticamente.

```bash
./scripts/run-tests.sh [PROJECT_ROOT] [--json]
```

Stacks: flutter, nextjs, node, python/pytest, go, rust.
Con `--json`: `{success, exit_code, stdout, stderr, duration_s, stack}`.

---

### run-lint.sh

Ejecuta el linter detectando el stack automáticamente.

```bash
./scripts/run-lint.sh [PROJECT_ROOT] [--json]
```

Stacks: flutter (`flutter analyze --no-fatal-infos`), python (`ruff check .`), go (`go vet`), rust (`cargo clippy`).

---

### sandbox-run.sh

Orquesta tests/lint en un contenedor Docker aislado.

```bash
./scripts/sandbox-run.sh <project_root> <tests|lint> [--json]
```

Flags Docker: `--network none --cap-drop ALL --memory 512m --read-only --tmpfs /tmp`.
Fallback a ejecución directa en host si Docker no está disponible.

---

### agent-metrics.sh

Dashboard de métricas desde la API de observabilidad.

```bash
./scripts/agent-metrics.sh [--json] [--task <task_id>] [--agents]
```

- Sin flags → resumen global con tabla de éxito por agente
- `--task <id>` → traza cronológica del ciclo
- `--agents` → métricas detalladas por agente
- `--json` → salida JSON directa de la API

---

### Dockerfile.sandbox

Imagen multi-stack para ejecución aislada. Incluye: Python 3.11, Flutter 3.19.6, Node.js 20, ruff, pytest.

```bash
docker build -f scripts/Dockerfile.sandbox -t agents-sandbox:latest .
```

---

### rag_indexer.py

Indexa documentos en el vector store (pgvector/OpenAI).

```bash
python scripts/rag_indexer.py --all --api-url http://localhost:8000
```

Indexa: `memoria_global.md`, `session_log.md`, secciones `AUTONOMOUS_LEARNINGS` de todos los agentes.

---

## 8. MCP servers

Configuración en `.mcp.json` (versión 1.0):

### filesystem

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-filesystem ${workspaceFolder}` |
| Agentes con acceso | researcher, auditor, backend, dbmanager, skill_installer |

Permite leer archivos del workspace sin depender de `context.files` manual.
Herramientas: `read_file`, `write_file`, `list_directory`, `search_files`, `create_directory`, `move_file`, `get_file_info`.

---

### github

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-github` |
| Env requerida | `GITHUB_TOKEN` |
| Agentes con acceso | devops |

Para crear PRs automáticamente tras push. Descripción del PR incluye `task_id`, `verification_cycle`, `verified_digest`.

---

### postgres

| Campo | Valor |
|---|---|
| Tipo | stdio |
| Comando | `npx -y @modelcontextprotocol/server-postgres ${env:SUPABASE_DB_URL}` |
| Env requerida | `SUPABASE_DB_URL` |
| Agentes con acceso | dbmanager, backend |

Queries directas y migraciones contra Supabase/Postgres sin pasar por la API REST.

---

### agents-api

| Campo | Valor |
|---|---|
| Tipo | http |
| URL | `${env:AGENTS_API_URL:-http://localhost:8000}` |
| Env requerida | `AGENTS_API_KEY` |
| Agentes con acceso | orchestrator, researcher, auditor |

Herramientas: `health_check`, `embed_document`, `retrieve_context` (RAG k=5), `log_agent_event`, `search_products`.

---

### Override de MCP por proyecto

Crear `.copilot/overrides.md` en la raíz del proyecto:

```markdown
## MCP Override

- agents-api.url: http://mi-servidor:9000
- filesystem.root: /ruta/custom
```

Las restricciones de `readonly.instructions.md` no pueden ser anuladas por overrides.

---

## 9. Sistema de memoria

### Ciclo completo

```
1. LECTURA (inicio de cada agente)
   └─► Lee memoria_global.md + AUTONOMOUS_LEARNINGS propio

2. ESCRITURA durante ciclo
   └─► session_logger → session_log.md (append-only)

3. CURACIÓN PARCIAL (Fase 5b, post-devops)
   └─► memory_curator extrae lecciones del ciclo → AUTONOMOUS_LEARNINGS
       Si agente supera 10 notas → archiva las más antiguas

4. CURACIÓN COMPLETA (cierre de sesión)
   └─► memory_curator lee historial completo → actualiza memoria_global.md
```

### Estructura de memoria_global.md

```markdown
## [YYYY-MM-DD] <id-del-ciclo> — Descripción corta

**Agentes:** <lista>
### Problema detectado / Causa raíz / Fix aplicado / Resultado
### Antipatrón (a evitar) / Patrón correcto
```

### Límites del sistema

| Recurso | Límite | Acción si se supera |
|---|---|---|
| AUTONOMOUS_LEARNINGS por agente | 10 notas | memory_curator archiva las más antiguas |
| session_log.md | 500 líneas | validate-memory.sh emite WARN — archivar manualmente |

### Últimas 5 entradas de memoria_global.md

```
[2026-04-07] routing-fix-v1.0.1 — Score Routing: 60% → 100%. Fix: reglas explícitas para dbmanager.
[2026-04-07] ciclo3-bio-perfil — Flujo DB→Backend→UI. Migración precede a implementación de lógica.
[2026-04-07] ciclo2-busqueda-endpoint — Índice GiST/GIN antes del endpoint. Cursor-pagination > OFFSET.
[2026-04-07] ciclo1-color-boton — Verificación WCAG AA obligatoria antes de entregar a auditor.
[2026-04-07] NetTask — Migración Django Auth + bugfix tachado de tareas + auditoría post-migración.
```

---

## 10. Session log

### Formato de entrada

```
[YYYY-MM-DD HH:MM] EVENT_TYPE | task: <task_id> | <from> → <to> | status: <s> | artifacts: [<lista>] | <notes>
```

EVENT_TYPE: `AGENT_TRANSITION` | `EVAL_TRIGGER` | `PHASE_COMPLETE` | `ERROR` | `ESCALATION`
`session_log.md` es `audit_trail_artifact` — excluido de `verified_files` y del digest.

### Cuándo archivar

Cuando `validate-memory.sh` detecta > 500 líneas: renombrar a `session_log_YYYY-MM-DD.md` y crear nuevo.

### Últimas 10 entradas del session_log.md actual

```
[2026-04-09 10:03] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | APROBAR_SIN_EVAL | verification_cycle: delta-v2.1.r4
[2026-04-09 10:58] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | verification_cycle: delta-v2.1.r4 | Pase 5
[2026-04-09 11:00] ESCALATION | task: delta-v2.1 | user → orchestrator | status: OVERRIDE | retry_count_reset: 4→0 | verification_cycle: delta-v2.1.override1.r0
[2026-04-09 11:05] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | verification_cycle: delta-v2.1.override1.r0 | Pase 6
[2026-04-09 11:25] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | APROBAR_SIN_EVAL | verification_cycle: delta-v2.1.override2.r0
[2026-04-09 11:30] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | verification_cycle: delta-v2.1.override2.r0 | Pase 7
[2026-04-09 11:35] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | verification_cycle: delta-v2.1.override2.r1
[2026-04-09 11:40] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | verified_digest: 781757fe... | Pase 8: index binding
[2026-04-09 11:50] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | verification_cycle: delta-v2.1.override3.r0
[2026-04-09 12:20] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | verified_digest: ee3b5c50... | Pase 11: verdified_digest consenso exigido
```

---

## 11. Arquitectura de archivos

```
.copilot/
├── .github/
│   ├── copilot-instructions.md         Instrucciones de stack para GitHub Copilot
│   └── workflows/
│       ├── ci.yml                       Pipeline CI (python, flutter, security, validate-agents)
│       └── rollback.yml                 Auto-revert en fallos de CI en main
├── .mcp.json                            Configuración de 4 servidores MCP
├── agents/
│   ├── analyst.agent.md
│   ├── auditor.agent.md
│   ├── backend.agent.md
│   ├── dbmanager.agent.md
│   ├── developer.agent.md
│   ├── devops.agent.md
│   ├── eval_runner.agent.md
│   ├── frontend.agent.md
│   ├── memoria_global.md               Memoria compartida persistente
│   ├── memory_curator.agent.md
│   ├── orchestrator.agent.md
│   ├── qa.agent.md
│   ├── red_team.agent.md
│   ├── researcher.agent.md
│   ├── session_logger.agent.md
│   ├── skill_installer.agent.md
│   ├── tdd_enforcer.agent.md
│   ├── api/
│   │   ├── main.py                      FastAPI app v3.1.0
│   │   ├── mcp_tools.py                 MCP tools layer (5 herramientas)
│   │   ├── observability.py             Logging JSON + /metrics endpoints
│   │   ├── requirements.txt
│   │   └── migrations/
│   │       └── 20260409_001_rag_memory_vectors.sql
│   ├── evals/
│   │   ├── eval_catalog.md              20 evaluaciones de referencia
│   │   └── eval_report_template.md
│   └── eval_outputs/                    Outputs de evals anteriores
├── instructions/
│   ├── git.instructions.md
│   ├── global.instructions.md
│   ├── readonly.instructions.md
│   └── stack-override.instructions.md
├── scripts/
│   ├── agent-metrics.sh
│   ├── Dockerfile.sandbox
│   ├── rag_indexer.py
│   ├── run-lint.sh
│   ├── run-tests.sh
│   ├── sandbox-run.sh
│   ├── token-report.sh
│   ├── validate-agents.sh
│   ├── validate-memory.sh
│   └── validate-stack.sh
├── config.json
├── session_log.md                       Audit trail append-only
└── SISTEMA_COMPLETO.md                  Este archivo
```

**Estructura en cada proyecto gestionado:**

```
<proyecto>/
├── .copilot/
│   ├── stack.md          Stack detectado + comandos de test y lint
│   └── overrides.md      (opcional) Override de instrucciones globales
└── skills_cache.md       (generado por skill_installer, con timestamp 24h)
```

---

## 12. Eval system

### Estado actual

Último reporte: `baseline_attempt_aca11a4_20260409_095901` → `status: ESCALATE`
Score: N/A. Evals correctas ejecutadas: **0/20**.
Motivo: sin infraestructura de runner end-to-end.

### Catálogo de 20 evaluaciones

| ID | Grupo | Descripción | Peso |
|---|---|---|---|
| eval-001 | routing | Tarea solo UI → solo frontend, sin dbmanager | alto |
| eval-002 | routing | Tarea solo backend → backend, sin dbmanager ni frontend | alto |
| eval-003 | routing | Tarea con cambio de esquema → dbmanager antes de backend | alto |
| eval-004 | routing | Tarea ambigua → analyst en Fase 0 | medio |
| eval-005 | routing | Bugfix → developer/backend, nunca dbmanager | alto |
| eval-006 | contratos | Formato director_report: campos obligatorios correctos | alto |
| eval-007 | contratos | Sufijos en paralelo: .audit, .qa, .redteam correctos | alto |
| eval-008 | contratos | Rechazo estructurado de auditor con archivo/línea/vector/sugerencia | alto |
| eval-009 | contratos | Rechazo estructurado de qa con missing_cases detallados | alto |
| eval-010 | reintentos | Reintento enriquecido: previous_output adjunto + corrección precisa | alto |
| eval-011 | reintentos | Escalación correcta: status ESCALATE tras 2 reintentos | alto |
| eval-012 | reintentos | devops rechaza sin triple aprobación (solo auditor) | alto |
| eval-013 | memoria | Curación parcial post-devops escribe en AUTONOMOUS_LEARNINGS | medio |
| eval-014 | memoria | Curación completa al cierre actualiza memoria_global.md | medio |
| eval-015 | memoria | Agente lee memoria antes de actuar (log visible en output) | medio |
| eval-016 | coordinación | orchestrator espera los tres veredictos (no avanza con dos) | alto |
| eval-017 | coordinación | orchestrator avanza solo con triple aprobación (no con doble) | alto |
| eval-018 | coordinación | Rechazo de auditor con qa y red_team pendientes → orchestrator no avanza | alto |
| eval-019 | coordinación | task_id correcto end-to-end en los tres agentes del paralelo | alto |
| eval-020 | coordinación | Timeout de un agente en el triple paralelo → orchestrator espera o escala | medio |

### Estado por eval (baseline)

Todos: `NOT_EXECUTED` — sin runner end-to-end instalado.

### Próximos pasos

- Implementar runner que invoque agentes reales en secuencia con fixtures de inputs
- Validador de outputs vs `Expected` para cada eval
- Establecer score baseline real antes de aplicar mejoras
- CI: ejecutar `modo: grupo` (routing + contratos) en cada PR

---

## 13. Historial de versiones

| Versión | Fecha | Cambios principales |
|---|---|---|
| v1.0.0 | 2026-04-07 | Sistema base: orchestrator, backend, frontend, developer, auditor, qa, devops, session_logger, memory_curator |
| v1.0.1 | 2026-04-07 | Fix routing para dbmanager (Score 60% → 100%) |
| v2.0.0 | 2026-04-07 | Añadido: red_team (verificador paralelo), tdd_enforcer, researcher, skill_installer, analyst |
| v2.1.0 | 2026-04-09 | verified_digest canónico; VERIFICACIÓN DE BRANCH OBLIGATORIA; 4 instruction files; 4 scripts de validación; evals 018-020 para triple paralelo |
| v2.1.x | 2026-04-09 | Pases 5-11: verification_cycle único irrepetible; igualdad exacta verified_files; branch_name requerido; verified_digest consensuado; index binding en devops |
| v3.1.0 | 2026-04-09 | Integración MCP (4 servidores); RAG con pgvector; sandbox Docker aislado; copilot-instructions.md; Observabilidad (logging JSON, /metrics); contratos v3.1 y alineación del workspace local con `agents/api` |

---

## 14. Guía de inicio rápido

1. **Clona el repositorio** `RCarribero/agents` y abre `.copilot/` en VS Code.

2. **Crea `.env`** en la raíz con las variables requeridas:
   ```
   SUPABASE_URL=https://tu-proyecto.supabase.co
   SUPABASE_KEY=tu-service-role-key
   SUPABASE_DB_URL=postgresql://...
   AGENTS_API_URL=http://localhost:8000
   AGENTS_API_KEY=tu-clave-interna
   GITHUB_TOKEN=tu-github-pat
   OPENAI_API_KEY=sk-...
   ```

3. **Instala la API interna:**
   ```bash
   cd agents/api && pip install -r requirements.txt
   uvicorn api.main:app --reload
   ```

4. **Aplica la migración DB** (`agents/api/migrations/20260409_001_rag_memory_vectors.sql`) en Supabase.

5. **Detecta el stack** de tu proyecto:
   ```bash
   ./scripts/validate-stack.sh /ruta/a/tu/proyecto
   ```

6. **Verifica la integridad del sistema:**
   ```bash
   ./scripts/validate-agents.sh
   ./scripts/validate-memory.sh
   ./scripts/token-report.sh
   ```

7. **Indexa documentación existente** en el vector store:
   ```bash
   python scripts/rag_indexer.py --all --api-url http://localhost:8000
   ```

8. **Envía tu primera tarea:**
   ```
   @orchestrator Implementa [tu tarea aquí]
   ```

9. **Monitorea en tiempo real:**
   ```bash
   tail -f session_log.md
   ./scripts/agent-metrics.sh
   ```

10. **Al cerrar la sesión**, invoca `memory_curator` (modo completo) para consolidar lecciones en `memoria_global.md`.

---

*Generado automáticamente el 2026-04-09 por GitHub Copilot (Claude Sonnet 4.6)*
