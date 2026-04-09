# Sistema Multi-Agente — Documentación Completa

**Versión:** v2.1 (inferida del contenido de los contratos y del historial de sesión)
**Fecha:** 9 de abril de 2026
**Stack activo:** No existe `.copilot/stack.md` — stack detectado del proyecto de referencia: FastAPI + Supabase (backend), Flutter/Dart (frontend), Python, Dart/Riverpod

---

## 1. Flujo de ejecución

```
Usuario
  │
  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR  (clasifica la tarea)                                     │
├─────────────────────────────────────────────────────────────────────────┤
│  ¿Pregunta, consulta o explicación?                                     │
│    └─► MODO CONSULTA ──► responde directamente (researcher opcional)    │
│                                                                         │
│  ¿Cambio < 3 archivos, sin esquema, bajo riesgo?                        │
│    └─► MODO RÁPIDO ────► Fase 2b + Fase 4 solamente                     │
│                           Si el implementador escala ──► MODO COMPLETO │
│                                                                         │
│  ¿Feature, migración, multi-módulo o riesgo alto?                       │
│    └─► MODO COMPLETO ──► flujo completo (abajo)                         │
└─────────────────────────────────────────────────────────────────────────┘

MODO COMPLETO — Flujo completo de fases

Fase -1   skill_installer
           └─► skill_context (nunca bloquea; null si falla)
               │
Fase 0a   researcher
           └─► research_brief (solo si hay código afectado)
               │
Fase 0    analyst (solo si dominio desconocido o tarea compleja)
           └─► ideas priorizadas
               │
Fase 1    dbmanager (solo si hay cambio de esquema)
           └─► SQL idempotente + backward-compatible
               │
Fase 2a   tdd_enforcer (si aplica lógica nueva)
           └─► tests en RED + test_output
               │
Fase 2    backend | frontend | developer
  ┌────────────────────────────────────┐
  │  objetivo: tests en GREEN          │
  │  (si viene de tdd_enforcer)        │
  └────────────────────────────────────┘
               │
               │  si falla 2 veces ──► ESCALATE → human
               │
Fase 3    [PARALELO] auditor ∥ qa ∥ red_team
  ┌─────────────┬──────────────┬──────────────┐
  │  auditor    │  qa          │  red_team    │
  │  APROBADO   │  CUMPLE      │  RESISTENTE  │
  │  RECHAZADO  │  NO CUMPLE   │  VULNERABLE  │
  └─────────────┴──────────────┴──────────────┘
       │               │               │
       └───────────────┴───────────────┘
               │  espera los 3 veredictos
               │
  ┌────────────────────────────────────────────────────────┐
  │  auditor  │ qa        │ red_team  │ Acción              │
  │  APROBADO │ CUMPLE    │RESISTENTE │ → devops (Fase 4)   │
  │  RECHAZADO│ *         │ *         │ → retry implementador│
  │  *        │ NO CUMPLE │ *         │ → retry implementador│
  │  *        │ *         │VULNERABLE │ → retry implementador│
  │  retry_count ≥ 2      │           │ → ESCALATE → human  │
  └────────────────────────────────────────────────────────┘
               │  triple aprobación
               ▼
Fase 4    devops
           └─► commit + push (Conventional Commits)
               │
Fase 5    session_logger (tras cada transición relevante)
           └─► memoria_global.md (append-only)
          memory_curator parcial (tras cada ciclo exitoso)
           └─► AUTONOMOUS_LEARNINGS de agentes participantes
               │
  [cierre de sesión]
          memory_curator completo
           └─► memoria_global.md consolidada

MODO RÁPIDO — Flujo mínimo

Fase 2b   backend | frontend | developer (sin TDD, sin researcher)
           └─► lint/analyze antes de entregar
               │ si detecta complejidad no prevista: ESCALATE → MODO COMPLETO
               ▼
Fase 4    devops

GESTIÓN DE REINTENTOS Y OVERRIDES

  retry_count < 2:  re-invocar implementador con director_report(s) de rechazo
  retry_count ≥ 2:  ESCALATE → human
  override humano:  nuevo ciclo supervisado
                    verification_cycle = <task_id>.override<N>.r0
                    EVAL_TRIGGER fresco obligatorio si toca .agent.md
```

---

## 2. Clasificador de complejidad

### Señales de clasificación

| Señal en la tarea | Modo |
|---|---|
| "¿qué", "cómo", "dónde", "explica", "muéstrame" | CONSULTA |
| "cambia el color", "corrige el texto", "arregla este typo" | RÁPIDO |
| "añade un campo simple", "cambia este mensaje" | RÁPIDO |
| "falla", "bug", "error" + cambio localizado obvio | RÁPIDO |
| "implementa", "crea", "añade feature", "nueva pantalla" | COMPLETO |
| "migración", "tabla", "RLS", "esquema" | COMPLETO |
| "refactor", "reestructura", "mueve módulo" | COMPLETO |
| Ambiguo o no clasificable | COMPLETO (por defecto seguro) |

### Condiciones de cada modo

**MODO CONSULTA**
- La tarea es una pregunta, consulta o petición de explicación
- Acción: responder directamente; `researcher` opcional si hace falta contexto de lectura
- Sin fases, sin agentes de ejecución

**MODO RÁPIDO**
- Menos de 3 archivos afectados
- Sin cambio de esquema ni migraciones
- Sin nuevos providers, servicios o dependencias
- El cambio es reversible en menos de 1 minuto
- Fases activas: Fase 2b + Fase 4

**MODO COMPLETO**
- Feature nueva, toca esquema, afecta múltiples módulos o riesgo alto
- Cualquier cosa no clasificable cae aquí (por defecto seguro)
- Fases activas: flujo completo (-1 a 5)

### Escalación de RÁPIDO a COMPLETO

El implementador puede escalar de MODO RÁPIDO si detecta:
- Más archivos afectados de los esperados
- Dependencias no previstas
- Riesgo no obvio en el cambio

Formato:
```xml
<director_report>
task_id: quick-001
status: ESCALATE
next_agent: orchestrator
escalate_to: none
summary: Cambio más complejo de lo esperado — requiere MODO COMPLETO
reason: El fix de UI toca el provider de estado — riesgo de regresión
</director_report>
```

El orchestrator recibe la escalación, reclasifica como MODO COMPLETO y reinicia el flujo desde Fase 0a con el contexto acumulado.

---

## 3. Agentes

### Agentes invocables por el usuario

---

#### orchestrator

| Campo | Valor |
|---|---|
| **Nombre** | orchestrator |
| **Modelo** | GPT-5.4 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | sí |

**Rol:** Director de orquesta. Recibe tareas del usuario, crea el plan de ejecución y delega a los sub-agentes correctos en el orden correcto.

**Cuándo se invoca:** Siempre. Es el punto de entrada de toda tarea.

**Flujo interno:**
1. Lee `memoria_global.md` antes de planificar
2. Clasifica la tarea (CONSULTA / RÁPIDO / COMPLETO)
3. Produce el plan con MODO, Motivo y Fases activas
4. Delega por fases según el modo
5. Sincroniza el paralelo de Fase 3 (espera los tres veredictos)
6. Habilita Fase 4 solo con triple aprobación + verificación de bundle
7. Gestiona reintentos con `retry_count` y escalación a human
8. Dispara `session_logger` tras cada transición relevante
9. Dispara `memory_curator` parcial tras cada ciclo exitoso

**Reglas clave:**
- Nunca implementa código, nunca hace commits, nunca revisa seguridad él mismo
- Clasifica siempre antes de planificar (primer paso obligatorio)
- Si retry_count ≥ 2, escala a human con historial completo
- `devops` solo se habilita con los tres veredictos en el mismo `verification_cycle`
- Los contratos `.agent.md` solo se modifican bajo regla de protección de agentes (eval antes y después)
- Conserva autoridad exclusiva para aprobar y revertir cambios en `.agent.md`

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string (tarea del usuario)",
  "retry_count": 0,
  "context": {
    "files": ["archivos relevantes del proyecto"],
    "previous_output": "historial de sesión si aplica",
    "constraints": ["convenciones del proyecto"],
    "skill_context": { "...": "provisto por skill_installer en Fase -1, opcional" },
    "research_brief": { "...": "provisto por researcher en Fase 0a, opcional" }
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
agents_invoked: <lista de agentes usados>
artifacts: <resumen de entregables>
next_steps: <si aplica>
escalate_to: human | none
summary: <qué se hizo + estado final>
</director_report>
```

**AUTONOMOUS_LEARNINGS:** No aplica (el orchestrator no tiene sección propia de aprendizajes).

---

#### analyst

| Campo | Valor |
|---|---|
| **Nombre** | analyst |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | 0.7 |
| **Invocable por usuario** | sí |

**Rol:** Analista estratégico. Detecta funcionalidades ausentes y genera ideas accionables de mejora, arquitectura y producto.

**Cuándo se invoca:** Fase 0 del MODO COMPLETO cuando el dominio es desconocido o la tarea es compleja. También cuando el orchestrator lo activa tras 3+ ciclos de deuda técnica.

**Reglas clave:**
- Lee `memoria_global.md` antes de analizar (no repite ideas ya documentadas)
- Genera ideas en 4 categorías: Arquitectura, Rendimiento, Producto, Features ausentes
- Máximo 10 ideas por sesión, priorizadas por ratio impacto/esfuerzo
- Solo sugiere features ausentes con evidencia concreta de ausencia en el código
- Su output alimenta directamente el plan del orchestrator para las fases siguientes
- Auto-aprendizaje vía campo `notes` con prefijo `APRENDIZAJE:` (el memory_curator lo cura)

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "retry_count": 0,
  "context": {
    "files": ["archivos relevantes del proyecto a analizar"],
    "previous_output": "output del orchestrator o contexto adicional",
    "constraints": ["restricciones o foco del análisis"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: <lista de ideas generadas>
next_agent: orchestrator
escalate_to: human | none
summary: <dominio detectado + nº ideas + nº features ausentes>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### eval_runner

| Campo | Valor |
|---|---|
| **Nombre** | eval_runner |
| **Modelo** | GPT-5.4 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | sí |

**Rol:** Sistema de evaluación automática. Ejecuta evals de referencia contra el sistema de agentes y emite informes de salud.

**Cuándo se invoca:** Cuando el orchestrator activa la Regla de protección de agentes (antes y después de modificar cualquier `.agent.md`). También invocable directamente por el usuario para medir el estado del sistema.

**Reglas clave:**
- Nunca modifica el sistema que evalúa — es observador pasivo puro
- Nunca modifica `.agent.md` ni `memoria_global.md`
- Timeout estricto de 5 minutos por eval; si supera = FAIL automático
- Guarda todos los outputs en `eval_outputs/`
- Compara versiones y genera tendencia histórica
- Si la invocación directa no es posible, ejecuta en modo simulación (PARTIAL)

**Contrato de entrada:**
```json
{
  "eval_ids": ["eval-001", "eval-002"] | null,
  "sistema_version": "string",
  "modo": "full | grupo | single",
  "grupo": "routing | contratos | reintentos | memoria | coordinacion | null",
  "eval_id": "eval-NNN | null",
  "requiere_flujo_completo": true | false | null
}
```

**Contrato de salida:**
```xml
<eval_report>
version: <sistema_version>
date: <YYYY-MM-DD HH:MM:SS>
total: <número de evals ejecutadas>
pass: <número de PASS>
fail: <número de FAIL>
partial: <número de PARTIAL>
score: <porcentaje de éxito, 0-100>
critical_failures: <número de fallos críticos>
report_file: <ruta del informe markdown generado>
</eval_report>
```

**AUTONOMOUS_LEARNINGS:** No tiene sección propia.

---

### Agentes internos (por orden de aparición en el flujo)

---

#### skill_installer

| Campo | Valor |
|---|---|
| **Nombre** | skill_installer |
| **Modelo** | Claude Haiku 4.5 |
| **Temperatura** | 0.0 |
| **Invocable por usuario** | no |

**Rol:** Detecta el stack del proyecto e instala/prepara los skills relevantes. Primera acción de cada sesión.

**Cuándo se invoca:** Fase -1 del MODO COMPLETO. Primera acción de cada sesión, antes que cualquier otro agente.

**Reglas clave:**
- Verifica el cache (`skills_cache.md`) antes de detectar el stack; si < 24h, usa cache
- Detecta stack desde `.copilot/stack.md` o manifests (`pubspec.yaml`, `package.json`, etc.)
- Si `autoskills` no está disponible, no falla: anota `autoskills: unavailable` y continúa
- Nunca bloquea el flujo: si falla devuelve `status: SKIPPED` con `skill_context: null`
- El `skill_context` se propaga como campo adicional del context a todos los agentes siguientes

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "context": {
    "workspace_root": "ruta raíz del proyecto",
    "constraints": ["convenciones del proyecto"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | SKIPPED
artifacts: ["skills_cache.md"]
next_agent: researcher
escalate_to: none
skill_context: <objeto JSON con skills instalados, o null si falla>
summary: <skills detectados + estado de cache>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### researcher

| Campo | Valor |
|---|---|
| **Nombre** | researcher |
| **Modelo** | Claude Opus 4.6 |
| **Temperatura** | 0.3 |
| **Invocable por usuario** | no |

**Rol:** Analiza el estado actual del módulo afectado y produce un research_brief con contexto, archivos relevantes y riesgos antes de que comience la implementación.

**Cuándo se invoca:** Fase 0a del MODO COMPLETO, cuando hay código existente afectado. También opcional en MODO CONSULTA si el orchestrator necesita contexto de lectura.

**Reglas clave:**
- Solo lectura — nunca crea, modifica ni elimina archivos
- Mapea el módulo completo (todos los archivos que tocan la funcionalidad, no solo el obvio)
- Detecta tests existentes; si no hay, marca `test_coverage_estimate: "ninguno"` como riesgo de severidad media
- Identifica el patrón arquitectónico dominante del módulo
- Si el riesgo es suficientemente alto, coloca `next_agent: analyst` en el informe

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "context": {
    "files": ["archivos y módulos mencionados en el objetivo"],
    "skill_context": { "...": "si fue provisto por skill_installer, opcional" },
    "constraints": ["convenciones del proyecto"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: []
next_agent: analyst (si aplica) | implementador
escalate_to: human | none
research_brief: <objeto JSON con el brief completo>
summary: <módulo investigado + principal riesgo detectado>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### dbmanager

| Campo | Valor |
|---|---|
| **Nombre** | dbmanager |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Arquitecto de datos orientado a producción. Diseña, migra y protege el esquema con foco en rendimiento, concurrencia y escalabilidad.

**Cuándo se invoca:** Fase 1 del MODO COMPLETO, solo si la tarea requiere cambios estructurales de esquema (CREATE TABLE, ALTER TABLE, ADD/DROP COLUMN, nueva RLS policy, índice no trivial sobre columna nueva). No se invoca para consultas, bugfixes de lógica ni optimizaciones sin cambio de índices.

**Reglas clave:**
- Migraciones solo en `supabase/migrations/*.sql`, idempotentes y backward-compatible
- RLS obligatoria con ENABLE ROW LEVEL SECURITY + policies basadas en `auth.uid()`
- Prohibido `USING (true)` salvo caso público documentado
- Estrategia de migrations: add → backfill → migrate → cleanup (nunca borrar columnas en caliente)
- Índices solo si hay query concreta que los justifique; documentar motivo en SQL
- Si falta información, escala a human antes de escribir SQL

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "retry_count": 0,
  "context": {
    "files": ["supabase/schema.sql", "archivos de migración relevantes"],
    "previous_output": "output del orchestrator",
    "constraints": ["convenciones del proyecto", "patrones de acceso esperados"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: <lista de archivos SQL creados/modificados>
next_agent: backend | developer
escalate_to: human | none
summary: <entidades afectadas + tipo de cambio>
</director_report>
```

**AUTONOMOUS_LEARNINGS:** No tiene sección documentada en el archivo.

---

#### tdd_enforcer

| Campo | Valor |
|---|---|
| **Nombre** | tdd_enforcer |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | 0.0 |
| **Invocable por usuario** | no |

**Rol:** Garantiza que los tests estén en RED antes de que el implementador escriba código de producción. Solo escribe tests, nunca producción.

**Cuándo se invoca:** Fase 2a del MODO COMPLETO, cuando aplica lógica nueva.

**Reglas clave:**
- Solo escribe tests, nunca código de producción
- Los tests deben compilar pero fallar en runtime (RED válido)
- Cubre: happy path, al menos un caso de error, al menos una validación fallida
- Si los tests ya existen en RED y son suficientes, certifícalos y pasa el relevo
- Si los tests ya están en GREEN (funcionalidad ya implementada): ESCALATE → human
- Usa el framework de tests del proyecto (no introduce nuevos sin declararlo)

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "context": {
    "files": ["archivos relevantes del módulo a testear"],
    "research_brief": { "...": "si fue provisto por researcher, opcional" },
    "skill_context": { "...": "si fue provisto por skill_installer, opcional" },
    "constraints": ["convenciones de tests del proyecto"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: <lista de archivos de test creados/modificados>
next_agent: backend | frontend | developer
escalate_to: human | none
tdd_status: RED
test_output: <output literal del runner de tests mostrando los fallos>
summary: <nº tests escritos + qué comportamientos cubren>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### backend

| Campo | Valor |
|---|---|
| **Nombre** | backend |
| **Modelo** | haiku |
| **Temperatura** | 0.0 |
| **Invocable por usuario** | no |

**Rol:** Desarrollador backend. Implementa lógica de servidor de forma eficiente, limpia y robusta.

**Cuándo se invoca:** Fase 2 del flujo cuando la tarea toca lógica de servidor, APIs o datos.

**Reglas clave:**
- Perímetro solo en workspace local; sin permisos git
- Lee el motivo de rechazo antes de tocar código en reintentos
- Cero cháchara: no explica, implementa directamente
- No modifica tests; si un test parece incorrecto, reporta conflicto y escala
- Corre `flutter analyze` (o linter equivalente) antes de entregar; corrige errores
- No introduce dependencias externas sin listarlas en el `director_report`
- Auto-aprendizaje vía campo `notes` con prefijo `APRENDIZAJE:`

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "retry_count": 0,
  "context": {
    "files": ["archivos relevantes"],
    "branch_name": "string",
    "previous_output": "output del orchestrator o feedback del auditor",
    "rejection_reason": "string (solo en reintentos)",
    "constraints": ["convenciones del proyecto"],
    "skill_context": { "...": "provisto por skill_installer, opcional" },
    "research_brief": { "...": "provisto por researcher, opcional" },
    "tdd_status": "RED (si viene de tdd_enforcer)",
    "test_output": "output del runner de tests en RED, opcional"
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: <lista de rutas creadas/modificadas>
next_agent: auditor ∥ qa ∥ red_team (Fase 3, paralelo)
escalate_to: human | none
summary: <1-2 líneas>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Validar input de búsqueda siempre con parámetros, nunca concatenar strings en queries dinámicas.
- Paginación por cursor (`id > last_seen`) preferible a OFFSET en tablas grandes.
- En PATCH de tarea con `usuarios_ids`, mantener validación estricta de membresía por proyecto y protegerla con test de regresión explícito para evitar reintroducir 400 por asignaciones inválidas.
- Al mover una tarea fuera de `terminado`, recalcular `completada` desde la columna destino y no conservar el estado previo.
- En transiciones `terminado`<->no `terminado`, centralizar una única regla de derivación (`completada = destino == terminado`) para evitar regresiones tras recarga.
```

---

#### frontend

| Campo | Valor |
|---|---|
| **Nombre** | frontend |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Especialista en UI. Implementa componentes, pantallas y flujos de usuario con foco en calidad visual y experiencia.

**Cuándo se invoca:** Fase 2 del flujo cuando la tarea toca UI, componentes visuales o flujos de usuario.

**Reglas clave:**
- Cero estilos inline; usa el sistema de estilos del proyecto
- Accesibilidad no es opcional (ARIA, teclado, contraste)
- No inventa lógica de negocio; si faltan datos o comportamiento, reporta el gap
- Responsivo por defecto (mobile + desktop)
- Componentes pequeños y reutilizables; preferred `shared/` si generalizable
- No introduce dependencias externas sin listarlas en el `director_report`

**Contrato de entrada/salida:** Igual a `backend` con campo adicional `branch_name` en context.

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Validar campos de texto largo con contador visual + validación de longitud para evitar overflow.
- **Migración de SDKs externos:** Al reemplazar un SDK, mantener interface de AuthContext idéntica para no romper componentes consumidores.
- **Magic strings de backend:** Verificar los valores reales del backend ANTES de implementar lógica condicional. Un typo causa bugs silenciosos.
- **Optimistic updates en drag & drop:** Actualizar estado local inmediatamente con `setTasks(updated)` antes de llamar al backend. Guardar `oldTasks` para rollback.
- **Constantes centralizadas:** Si hay >3 ocurrencias del mismo string literal, crear archivo de constantes.
- **Edición de asignaciones de tarea:** UI solo debe permitir `usuarios_ids` que pertenezcan al proyecto activo.
- **Compatibilidad de payloads:** Normalizar lectura de `usuarios_asignados` (objeto o id) y tipar el mapper frontend con el contrato real del backend.
```

---

#### developer

| Campo | Valor |
|---|---|
| **Nombre** | developer |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Desarrollador generalista. Recibe tests en RED y los pasa a GREEN.

**Cuándo se invoca:** Fase 2 cuando la tarea no es específicamente frontend ni backend, o como implementador directo en MODO RÁPIDO (Fase 2b).

**Reglas clave:**
- El único objetivo es hacer que los tests pasen a GREEN
- No modifica tests; si un test parece incorrecto, reporta y espera instrucciones
- Si tras dos iteraciones los tests siguen fallando, escala a human
- Sigue convenciones del proyecto: arquitectura existente, naming, patrones Riverpod
- Auto-aprendizaje vía campo `notes` con prefijo `APRENDIZAJE:`

**Contrato de entrada/salida:** Igual a `backend`.

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### auditor

| Campo | Valor |
|---|---|
| **Nombre** | auditor |
| **Modelo** | sonnet |
| **Temperatura** | 0.0 |
| **Invocable por usuario** | no |

**Rol:** Auditor de seguridad. Busca vulnerabilidades y antipatrones. Veredicto binario: APROBADO o RECHAZADO.

**Cuándo se invoca:** Fase 3 en paralelo con `qa` y `red_team`.

**Reglas clave:**
- Analiza todo el código entregado sin excepciones
- Busca: SQL/NoSQL injection, XSS, fugas de memoria, secretos hardcodeados, RLS bypass, race conditions, dependencias vulnerables, bucles infinitos
- Clasificación de severidad: Crítico / Alto / Medio
- Cualquier fallo crítico = RECHAZADO con explicación técnica precisa (archivo, línea, riesgo, vector, corrección)
- No opina sobre estilo ni preferencias de formato
- Debe emitir `branch_name`, `verified_files`, `verified_digest` y `verification_cycle` en su report

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "retry_count": 0,
  "context": {
    "files": ["archivos a auditar"],
    "branch_name": "rama del ciclo propagada por el orchestrator",
    "previous_output": "output del backend/frontend/developer con status SUCCESS",
    "constraints": ["convenciones del proyecto"],
    "skill_context": { "...": "opcional" }
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>.audit
status: SUCCESS | REJECTED
veredicto: APROBADO | RECHAZADO
artifacts: <lista de hallazgos si rechazado>
next_agent: orchestrator
escalate_to: human | none
verification_cycle: <task_id>.r<retry_count>
branch_name: <rama del ciclo>
verified_files: <lista de archivos auditados — excluye session_log.md>
verified_digest: <hash del contenido exacto verificado>
rejection_reason: <motivo si REJECTED>
rejection_details: <estructura detallada si REJECTED>
summary: <veredicto + nº hallazgos + severidades>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Endpoints de búsqueda sin parámetros preparados = vector de inyección SQL crítico.
- RLS faltante en tablas consultadas públicamente = hallazgo automático de severidad Alta.
- **Console.log en producción:** Búsqueda global de `console.log/error/warn` es obligatoria. Si hay +10 ocurrencias sin config de terser para eliminarlos en build, es hallazgo de severidad MEDIA.
- **Error messages sin sanitizar:** Si `error.message` se renderiza en UI sin mapeo a mensajes genéricos, es hallazgo MEDIA. Stack traces exponen arquitectura interna.
```

---

#### qa

| Campo | Valor |
|---|---|
| **Nombre** | qa |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Verificación funcional. Comprueba que la implementación cumple el objetivo definido. Veredicto binario: CUMPLE o NO CUMPLE.

**Cuándo se invoca:** Fase 3 en paralelo con `auditor` y `red_team`.

**Reglas clave:**
- Solo funcionalidad; no busca vulnerabilidades de seguridad
- Lee el `objective` del plan original antes de revisar código
- Ejecuta tests automatizados si existen; establece `test_status: GREEN | FAILED | NOT_APPLICABLE`
- Precondición: solo actúa si `previous_output` contiene `status: SUCCESS` del implementador
- Debe emitir `branch_name`, `verified_files`, `verified_digest`, `test_status` y `verification_cycle`

**Contrato de entrada:** Similar a `auditor` con `branch_name` requerido.

**Contrato de salida:**
```
<director_report>
task_id: <id>.qa
status: SUCCESS | REJECTED | ESCALATE
veredicto: CUMPLE | NO CUMPLE
artifacts: none
next_agent: orchestrator
escalate_to: human | none
verification_cycle: <task_id>.r<retry_count>
branch_name: <rama del ciclo>
verified_files: <lista de archivos verificados — excluye session_log.md>
verified_digest: <hash del contenido exacto verificado>
test_status: GREEN | FAILED | NOT_APPLICABLE
summary: <veredicto + gaps funcionales>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Campos de texto sin límite en UI = gap funcional, debe rechazarse aunque backend valide.
- Endpoint de búsqueda vacía debe devolver lista vacía, no error 500.
- **Testing por prioridad:** Ante múltiples endpoints, verificar primero los críticos (login, register).
- **Arquitectura frontend-backend:** Si frontend y backend usan stacks de autenticación diferentes, el sistema es 0% funcional. NO CUMPLE inmediato.
- **Optimistic updates:** Verificar que el rollback en caso de error está implementado.
- **Pass rate con fallos esperados:** Un 88.9% puede ser 100% funcional si el único fallo es comportamiento esperado. Analizar contexto.
- En edición de tarea, agregar caso QA obligatorio: intentar asignar usuario fuera del proyecto debe estar bloqueado en UI.
- Caso QA obligatorio en tablero: mover de `terminado` a otra columna + F5 debe dejar `completada=false` de forma persistente.
- Validar matriz de permisos en transiciones `terminado`<->no `terminado`: viewer NO reabre, editor/owner SI.
```

---

#### red_team

| Campo | Valor |
|---|---|
| **Nombre** | red_team |
| **Modelo** | GPT-5.4 |
| **Temperatura** | 0.5 |
| **Invocable por usuario** | no |

**Rol:** Atacante. Busca inputs maliciosos, edge cases y asunciones rotas. Veredicto binario: RESISTENTE o VULNERABLE.

**Cuándo se invoca:** Fase 3 en paralelo con `auditor` y `qa`.

**Reglas clave:**
- Nunca modifica código; es observador hostil puro
- Busca: inputs maliciosos, edge cases de negocio, race conditions, asunciones rotas, privilege escalation
- No repite el trabajo del auditor (no cubre OWASP clásico, solo lo referencia)
- Verdicto VULNERABLE si al menos un hallazgo de severidad crítica o alta
- Nunca habilita Fase 4 directamente; siempre devuelve al orchestrator
- Debe emitir `branch_name`, `verified_files`, `verified_digest` y `verification_cycle`

**Contrato de entrada:** Similar a `auditor` con `branch_name` requerido en context.

**Contrato de salida:**
```
<director_report>
task_id: <id>.redteam
status: SUCCESS | ESCALATE
veredicto: RESISTENTE | VULNERABLE
artifacts: []
next_agent: orchestrator
escalate_to: human | none
verification_cycle: <task_id>.r<retry_count>
branch_name: <rama del ciclo>
verified_files: <lista de archivos atacados — excluye session_log.md>
verified_digest: <hash del contenido exacto verificado>
vulnerabilities: <lista de hallazgos si VULNERABLE, vacío si RESISTENTE>
summary: <veredicto + nº vectores probados + hallazgos clave>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

#### devops

| Campo | Valor |
|---|---|
| **Nombre** | devops |
| **Modelo** | Claude Sonnet 4.6 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Único agente con permisos para tocar el repositorio. Hace el commit y el push.

**Cuándo se invoca:** Fase 4, solo cuando se cumplen las cuatro condiciones: `auditor` APROBADO + `qa` CUMPLE + `red_team` RESISTENTE + `test_status` GREEN o NOT_APPLICABLE.

**Reglas clave:**
- Solo actúa con cuádruple condición verificada
- Valida correlación interna del bundle: los tres veredictos deben ser del mismo ciclo (mismo `task_id`, `verification_cycle`, `verified_files`, `branch_name` y `verified_digest`)
- Pre-validación: `context.files == context.verified_files` (igualdad exacta) antes de aceptar el bundle
- Recalcula `verified_digest` sobre el working tree antes de ejecutar cualquier commit
- Index binding: reconstruye staging limpio solo con `verified_files`, recomputa digest del snapshot stageado y lo compara contra `verified_digest`
- Commits en formato Conventional Commits; incluye trailer Co-authored-by Copilot
- Commits atómicos (un cambio lógico por commit)
- Push a `context.branch_name` explícito; nunca asume `main`

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "string",
  "context": {
    "files": ["archivos a commitear — igualdad exacta con verified_files"],
    "branch_name": "rama destino (requerido explícito)",
    "verification_cycle": "identificador del ciclo actual",
    "verified_files": ["lista exacta de archivos verificados"],
    "verified_digest": "hash del contenido exacto verificado",
    "eval_gate_status": "PASSED | SKIPPED_BY_AUTHORIZATION",
    "previous_output": "bundle consolidado con los tres veredictos"
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | REJECTED | ESCALATE
artifacts: <lista de commits realizados>
next_agent: session_logger + memory_curator
escalate_to: human | none
summary: <nº commits + rama + estado del push>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Migraciones de DB deben incluirse en commit separado (tipo `feat(db):`) antes del commit de lógica.
- Commits de features completas (DB+backend+frontend) deben dividirse en 3 commits atómicos con orden de dependencia.
```

---

#### session_logger

| Campo | Valor |
|---|---|
| **Nombre** | session_logger |
| **Modelo** | Claude Haiku 4.5 |
| **Temperatura** | 0.0 |
| **Invocable por usuario** | no |

**Rol:** Registra cada transición de agente en `session_log.md` con append-only. No bloquea el flujo si falla.

**Cuándo se invoca:** Tras cada transición relevante del orchestrator — especialmente después de Fase 2a, Fase 3, Fase 4 y siempre tras ESCALATE.

**Reglas clave:**
- Append-only estricto; nunca sobreescribe `session_log.md`
- Cada entrada ocupa exactamente una línea
- Si falla por cualquier motivo, devuelve `status: SKIPPED` y nunca propaga el error
- `session_log.md` es audit_trail_artifact: no forma parte de `verified_files` ni del `verified_digest`
- Para eventos EVAL_TRIGGER y ciclos de override: incluye `retry_count`, `verification_cycle`, `branch_name`, `verified_digest` y `eval_authorization_scope` en `notes`
- Verifica consistencia `task_id` ↔ `verification_cycle`: el prefijo del ciclo debe coincidir con el `task_id` base

**Formato de entrada en el log:**
```
[YYYY-MM-DD HH:MM] <EVENT_TYPE> | task: <task_id> | <from_agent> → <to_agent> | status: <status> | artifacts: <lista> | <notes>
```

**Esquema canónico EVAL_TRIGGER:**
```
[YYYY-MM-DD HH:MM] EVAL_TRIGGER | task: <id> | orchestrator → eval_runner | status: APROBADO|REJECTED|SKIPPED | artifacts: [<ruta/exacta.agent.md>] | pre: XX% → post: YY% | verification_cycle: <task_id>.r<N> | retry_count: N [| escalado: human]
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | SKIPPED
artifacts: ["session_log.md"]
next_agent: none
escalate_to: none
summary: <entrada registrada en 1 línea>
</director_report>
```

**AUTONOMOUS_LEARNINGS:** No tiene sección propia (no autoedita su `.agent.md`).

---

#### memory_curator

| Campo | Valor |
|---|---|
| **Nombre** | memory_curator |
| **Modelo** | GPT-5.4 |
| **Temperatura** | no especificada |
| **Invocable por usuario** | no |

**Rol:** Extrae lecciones aprendidas y actualiza la memoria global. Agente terminal del flujo.

**Cuándo se invoca:** Modo parcial tras cada ciclo exitoso (post-devops). Modo completo al cierre de sesión.

**Reglas clave:**
- Modo parcial: solo toca `AUTONOMOUS_LEARNINGS` de agentes participantes; NO toca `memoria_global.md`
- Modo completo: consolida a `memoria_global.md`; cura notas de todos los agentes; elimina redundantes
- Máximo 10 notas por agente en `AUTONOMOUS_LEARNINGS`; archiva las más antiguas si se excede
- `memoria_global.md` mantiene orden cronológico inverso (más reciente primero)
- Lee el historial completo antes de escribir (no repite entradas ya existentes)
- Sé despiadadamente conciso

**Contrato de entrada:**
```json
{
  "task_id": "string",
  "objective": "curación parcial | curación completa",
  "context": {
    "files": ["memoria_global.md", "archivos .agent.md con AUTONOMOUS_LEARNINGS"],
    "previous_output": "historial completo de la sesión",
    "constraints": ["concisión", "no repetir entradas existentes"]
  }
}
```

**Contrato de salida:**
```
<director_report>
task_id: <id>
status: SUCCESS | ESCALATE
artifacts: ["memoria_global.md", "agentes actualizados si aplica"]
next_agent: none
escalate_to: human | none
summary: <nº entradas añadidas + nº agentes curados>
</director_report>
```

**AUTONOMOUS_LEARNINGS actuales:**
```
## Notas operativas aprendidas
- Sin notas curadas todavía.
```

---

## 4. Skills

No se encontró carpeta `.github/skills/` en el repositorio. Las skills disponibles son las instaladas globalmente en `~/.agents/skills/` (gestionadas por `skill_installer`). El sistema detecta las skills del catálogo configurado en `config.json` y las instala via `autoskills`.

Las rutas de skills activas en este workspace son las instaladas en `c:\Users\RBX\.agents\skills\` (inferido de la estructura de sesión). A continuación se documentan las skills que aparecen referenciadas en el sistema:

| Skill | Descripción | Agentes que la usan |
|---|---|---|
| `flutter-ui-ux` | Desarrollo Flutter UI/UX con animaciones y widgets | `frontend`, `developer` (stack Flutter) |
| `supabase` | CLI de Supabase, migraciones, RLS, Edge Functions | `backend`, `dbmanager` (stack Supabase) |
| `supabase-nextjs` | Next.js con Supabase y Drizzle ORM | `frontend`, `backend` (stack Next.js+Supabase) |
| `i18n-expert` | Internacionalización y localización en React/TS | `frontend` |
| `tonejs` | Síntesis de audio y música en el navegador | `developer` (si el proyecto usa audio) |

---

## 5. Instruction files

No se encontraron archivos de instrucciones en la carpeta `instructions/` (la carpeta existe pero está vacía). Existe un archivo de backup `instructions/basedatos.instructions.md.bak.20260319-124014` pero no se cargó como archivo activo.

---

## 6. Prompt templates

No se encontró carpeta `.github/prompts/` en el repositorio. No hay prompt templates configurados en este sistema.

---

## 7. Validation scripts

No se encontraron scripts en la carpeta `scripts/` (la carpeta existe pero está vacía). El archivo `scripts/Start-AutonomousWorkflow.ps1.bak.20260319-124015` es un backup de un script anterior y no está activo.

---

## 8. MCP servers

No se encontró archivo `.mcp.json` en el repositorio. No hay servidores MCP explícitamente configurados.

La API de utilidad disponible en `agents/api/` no es un servidor MCP — es un microservicio FastAPI con endpoints de salud y búsqueda:

| Endpoint | Descripción |
|---|---|
| `GET /health` | Estado del servicio |
| `GET /ping` | Verificar conectividad |
| `GET /` | Información de la API |
| `POST /products/search` | Búsqueda de productos (requiere Supabase configurado) |

**Ejecución:**
```bash
# Activar entorno
python -m venv venv && venv\Scripts\activate
pip install -r requirements.txt

# Desarrollo
python main.py

# Producción
uvicorn main:app --host 0.0.0.0 --port 8000
```

**Variables de entorno requeridas:**
- `SUPABASE_URL` — URL del proyecto Supabase
- `SUPABASE_KEY` — Clave anon o service role

---

## 9. Sistema de memoria

### Ciclo completo de memoria

```
1. LECTURA (antes de actuar)
   Cada agente lee memoria_global.md y su propia sección
   AUTONOMOUS_LEARNINGS antes de planificar, implementar o
   verificar. Esto evita repetir errores documentados.

2. ESCRITURA DURANTE EJECUCIÓN (campo notes)
   Los agentes escriben aprendizajes con prefijo APRENDIZAJE:
   en el campo notes de su director_report. No autoeditan
   sus archivos .agent.md.

3. CURACIÓN PARCIAL (tras cada ciclo exitoso, post-devops)
   memory_curator modo parcial:
   - Extrae los notes con APRENDIZAJE: del historial del ciclo
   - Los añade a AUTONOMOUS_LEARNINGS de los agentes
     que participaron en el ciclo
   - NO toca memoria_global.md

4. CURACIÓN COMPLETA (al cierre de sesión)
   memory_curator modo completo:
   - Lee historial completo de la sesión
   - Consolida entradas nuevas en memoria_global.md
   - Promueve notas genéricas de AUTONOMOUS_LEARNINGS a
     memoria_global.md
   - Elimina notas redundantes o incorrectas
   - Mantiene máximo 10 notas por agente
```

### Estructura de `memoria_global.md`

```markdown
---
user-invocable: false
---
# Memoria Global del Sistema de Agentes

Historial de lecciones aprendidas durante sesiones de trabajo.
Consulta este archivo antes de cada implementación para evitar
errores conocidos y respetar convenciones establecidas.

---

## [YYYY-MM-DD] task_id — Título del ciclo

**Agentes:** <lista de agentes que participaron>

### Buenas prácticas
- ...

### Errores a evitar
- ...
```

### Estructura de `AUTONOMOUS_LEARNINGS` en cada agente

```markdown
<!-- AUTONOMOUS_LEARNINGS_START -->
## Notas operativas aprendidas
- <bullet conciso de la lección aprendida>
- <otro bullet>
<!-- AUTONOMOUS_LEARNINGS_END -->
```

### Límites del sistema de memoria

| Límite | Valor |
|---|---|
| Máximo notas por agente en AUTONOMOUS_LEARNINGS | 10 |
| Líneas máximas recomendadas para session_log.md | ~500 (inferido de la práctica) |
| session_log.md como artefacto | audit_trail_artifact — excluido de verified_files y verified_digest |

### Últimas 5 entradas de `memoria_global.md`

```markdown
## [2026-04-07] routing-fix-v1.0.1 — Reglas de routing para dbmanager

**Agentes:** orchestrator (corregido)

### Fix aplicado
[...]
Score grupo Routing: 60% → 100%
Score general: 80% → 93%

---

## [2026-04-07] ciclo3-bio-perfil — Campo bio en perfil de usuario

**Agentes:** dbmanager, backend, frontend, auditor, qa, devops

### Buenas prácticas
- Flujo completo DB→Backend→UI funciona sin fricción cuando la migración precede a la lógica.
- Campo de texto largo requiere validación a tres niveles: DB (CHECK length), backend (max chars), frontend (contador visual).
- Migración idempotente con backward compatibility: agregar columna nullable primero.

---

## [2026-04-07] ciclo2-busqueda-endpoint — Endpoint de búsqueda

**Agentes:** dbmanager, backend, auditor, qa, devops

### Buenas prácticas
- Índice de búsqueda full-text debe preceder al endpoint.
- Paginación por cursor > OFFSET en tablas con crecimiento esperado.
- RLS obligatoria en tablas consultadas.

---

## [2026-04-07] ciclo1-color-boton — Cambio de color en botón primario

**Agentes:** frontend, auditor, qa, devops

### Buenas prácticas
- Cambios cosméticos simples aprobables en un solo ciclo cuando respetan sistema de diseño.
- Verificación de contraste WCAG AA obligatoria antes de entregar a auditor (ratio ≥4.5:1).

---

## [2026-04-07] NetTask — Migración de autenticación y bugfixes

**Agentes:** frontend, qa, auditor, memory_curator

### Hallazgo 1: Migración Django Auth
- Frontend reescrito de Supabase Auth SDK a Django endpoints directos.
- Arquitectura resultante: UI → AuthContext → axios POST /api/auth/login → Django → JWT.
```

---

## 10. Session log

### Formato de cada entrada

```
[YYYY-MM-DD HH:MM] <EVENT_TYPE> | task: <task_id> | <from_agent> → <to_agent> | status: <status> | artifacts: <lista> | <notes>
```

**Tipos de evento:**
- `AGENT_TRANSITION` — cambio de agente en el flujo
- `EVAL_TRIGGER` — activación o bypass del gate de evals
- `PHASE_COMPLETE` — fase completada
- `ERROR` — error ocurrido
- `ESCALATION` — escalación a human o override de usuario

### Cuándo se archiva

`session_log.md` es un artefacto append-only. No se archiva ni se rota automáticamente. Se recomienda archivar manualmente cuando supera ~500 líneas. No forma parte de `verified_files` ni contribuye al `verified_digest` de ningún ciclo.

### Últimas 10 entradas del `session_log.md` actual

```
[2026-04-09 10:03] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | artifacts: [agents/orchestrator.agent.md, agents/auditor.agent.md, agents/developer.agent.md, agents/devops.agent.md, agents/session_logger.agent.md, agents/red_team.agent.md, agents/backend.agent.md, agents/frontend.agent.md, agents/qa.agent.md, agents/skill_installer.agent.md, agents/researcher.agent.md, agents/tdd_enforcer.agent.md] | APROBAR_SIN_EVAL — autorización explícita del usuario por falta de infraestructura baseline | retry_count: 4 | verification_cycle: delta-v2.1.r4

[2026-04-09 10:58] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | artifacts: [agents/red_team.agent.md, agents/auditor.agent.md, agents/qa.agent.md, agents/devops.agent.md, agents/orchestrator.agent.md, agents/session_logger.agent.md, session_log.md] | verification_cycle: delta-v2.1.r4 | retry_count: 4 | Pase 5: verification_cycle + verified_files añadidos a contratos Fase 3

[2026-04-09 11:00] ESCALATION | task: delta-v2.1 | user → orchestrator | status: OVERRIDE | artifacts: [] | instrucción explícita del usuario ("intentalo") tras ciclo con retry_count: 4; nuevo ciclo supervisado abierto con retry_count_reset: 4→0; verification_cycle: delta-v2.1.override1.r0

[2026-04-09 11:05] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | artifacts: [agents/qa.agent.md, agents/devops.agent.md, agents/orchestrator.agent.md, agents/session_logger.agent.md, session_log.md] | verification_cycle: delta-v2.1.override1.r0 | retry_count: 0 | Pase 6: test_status estructurado + bundle binding estricto en devops

[2026-04-09 11:25] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | artifacts: [agents/orchestrator.agent.md, agents/auditor.agent.md, agents/qa.agent.md, agents/red_team.agent.md, agents/devops.agent.md, agents/session_logger.agent.md, session_log.md] | APROBAR_SIN_EVAL — autorización explícita del usuario | verification_cycle: delta-v2.1.override2.r0 | retry_count: 0 | eval_gate_status: SKIPPED_BY_AUTHORIZATION

[2026-04-09 11:30] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | artifacts: [agents/orchestrator.agent.md, agents/auditor.agent.md, agents/qa.agent.md, agents/red_team.agent.md, agents/devops.agent.md, agents/session_logger.agent.md, session_log.md] | verification_cycle: delta-v2.1.override2.r0 | retry_count: 0 | branch_name: main | Pase 7: verification_cycle único no reutilizable + campo verified_digest en contratos Fase 3

[2026-04-09 11:35] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | agents/orchestrator.agent.md, ... | APROBAR_SIN_EVAL — autorización explícita | verification_cycle: delta-v2.1.override2.r1 | retry_count: 1 | eval_gate_status: SKIPPED_BY_AUTHORIZATION

[2026-04-09 11:40] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | ... | verification_cycle: delta-v2.1.override2.r1 | branch_name: main | verified_digest: 781757fe... | Pase 8: context.files==verified_files==bundle; verified_digest recalculado sobre working tree

[2026-04-09 12:15] EVAL_TRIGGER | task: delta-v2.1 | orchestrator → eval_runner | status: SKIPPED | artifacts: [agents/orchestrator.agent.md, agents/devops.agent.md, agents/auditor.agent.md, agents/qa.agent.md, agents/red_team.agent.md, agents/session_logger.agent.md] | APROBAR_SIN_EVAL — autorización explícita del usuario | verification_cycle: delta-v2.1.override4.r0 | retry_count: 0 | eval_gate_status: SKIPPED_BY_AUTHORIZATION | eval_authorization_scope: { task_id: delta-v2.1, verification_cycle: delta-v2.1.override4.r0, branch_name: main, verified_digest: ee3b5c50... }

[2026-04-09 12:20] AGENT_TRANSITION | task: delta-v2.1 | developer → auditor ∥ qa ∥ red_team | status: SUCCESS | artifacts: [agents/orchestrator.agent.md, agents/devops.agent.md, agents/auditor.agent.md, agents/qa.agent.md, agents/red_team.agent.md, agents/session_logger.agent.md] | verification_cycle: delta-v2.1.override4.r0 | branch_name: main | verified_digest: ee3b5c505331241a0de9ce1aaae16b037952b4a0291949d1f3d1b93a2500ca78 | Pase 11: verified_digest consenso exigido entre los tres reports; session_log.md declarado audit_trail_artifact
```

---

## 11. Arquitectura de archivos

### Árbol del repositorio `.copilot`

```
.copilot/                              ← Raíz del sistema de agentes
├── .git/                              ← Repositorio git del sistema
├── .gitignore                         ← Excluye artefactos locales de VS Code
├── config.json                        ← Configuración global (usuario, effortLevel, etc.)
├── command-history-state.json         ← Estado interno del historial de comandos
├── session_log.md                     ← Audit trail append-only de todas las transiciones
├── SISTEMA_COMPLETO.md                ← Este documento
│
├── agents/                            ← Contratos de todos los agentes del sistema
│   ├── orchestrator.agent.md          ← Director: planifica y coordina todo
│   ├── analyst.agent.md               ← Análisis estratégico y detección de features (Fase 0)
│   ├── researcher.agent.md            ← Investigación de código existente (Fase 0a)
│   ├── skill_installer.agent.md       ← Instalación de skills del stack (Fase -1)
│   ├── tdd_enforcer.agent.md          ← Tests en RED antes de implementar (Fase 2a)
│   ├── backend.agent.md               ← Implementador backend (Fase 2)
│   ├── frontend.agent.md              ← Implementador frontend (Fase 2)
│   ├── developer.agent.md             ← Implementador generalista (Fase 2/2b)
│   ├── dbmanager.agent.md             ← Arquitecto de datos (Fase 1)
│   ├── auditor.agent.md               ← Auditor de seguridad (Fase 3, paralelo)
│   ├── qa.agent.md                    ← Verificación funcional (Fase 3, paralelo)
│   ├── red_team.agent.md              ← Atacante: edge cases y race conditions (Fase 3, paralelo)
│   ├── devops.agent.md                ← Commit y push (Fase 4)
│   ├── session_logger.agent.md        ← Registro append-only (Fase 5)
│   ├── memory_curator.agent.md        ← Curación de memoria (Fase 5 / cierre)
│   ├── eval_runner.agent.md           ← Evaluación automática del sistema
│   ├── memoria_global.md              ← Memoria compartida de lecciones aprendidas
│   │
│   ├── evals/                         ← Catálogo y plantillas de evaluación
│   │   ├── eval_catalog.md            ← 20 evals de referencia (5 grupos)
│   │   └── eval_report_template.md    ← Plantilla para informes de eval
│   │
│   ├── eval_outputs/                  ← Resultados de evals ejecutadas
│   │   ├── .gitkeep
│   │   ├── baseline_attempt_aca11a4_20260409_095901.json
│   │   └── eval_report_aca11a4_20260409_095901.md
│   │
│   ├── api/                           ← Microservicio FastAPI de utilidad
│   │   ├── main.py                    ← Endpoints: /health, /ping, /products/search
│   │   ├── README.md
│   │   ├── requirements.txt           ← fastapi, uvicorn, supabase, pydantic, python-dotenv
│   │   ├── .env.example
│   │   ├── models/                    ← Modelos Pydantic
│   │   └── repositories/             ← Patrón Repository sobre Supabase
│   │
│   └── lib/                           ← Librería Dart de referencia
│       └── service.dart
│
├── instructions/                      ← Instruction files (.instructions.md) — actualmente vacía
├── scripts/                           ← Scripts de automatización — actualmente vacío
├── logs/                              ← Logs del sistema
├── restart/                           ← Artefactos de reinicio
├── runs/                              ← Historial de ejecuciones
├── ide/                               ← Configuración específica del IDE
└── session-state/                     ← Estado de sesiones del orquestador
    └── <uuid>/                        ← Una carpeta por sesión
        ├── events.jsonl
        ├── vscode.metadata.json
        ├── workspace.yaml
        ├── checkpoints/
        ├── files/
        └── research/
```

### Árbol `.copilot` recomendado por proyecto

Cada proyecto que use este sistema debe tener:
```
<proyecto>/
└── .copilot/
    ├── stack.md          ← Stack del proyecto (detectado por skill_installer)
    ├── overrides.md      ← Overrides MCP o configuración específica del proyecto
    └── skills_cache.md   ← Cache de skills instalados (generado por skill_installer, TTL 24h)
```

---

## 12. Eval system

### Estado actual (último informe disponible)

El único informe ejecutado hasta la fecha (`eval_report_aca11a4_20260409_095901.md`) es un **baseline fallido** — no existe infraestructura automatizada para correr evals end-to-end.

| Sección | Estado | Motivo |
|---|---|---|
| Routing | NOT_EXECUTED | Sin invocación real al orchestrator |
| Contratos | NOT_EXECUTED | Sin outputs reales de agentes |
| Reintentos | NOT_EXECUTED | Sin runner que encadene rechazos y retry_count |
| Memoria | NOT_EXECUTED | Sin ciclos reales para observar curación |
| Coordinación | NOT_EXECUTED | Sin infraestructura para paralelos |

**Score general:** N/A (0/20 evals ejecutadas)

### Catálogo de evals (20 evals en 5 grupos)

| Eval | Grupo | Descripción | Peso |
|---|---|---|---|
| eval-001 | Routing | Tarea solo UI — dbmanager omitido | alto |
| eval-002 | Routing | Tarea solo backend — dbmanager y frontend omitidos | alto |
| eval-003 | Routing | Tarea con esquema — dbmanager invocado antes de backend | alto |
| eval-004 | Routing | Tarea ambigua — analyst invocado primero | medio |
| eval-005 | Routing | Tarea de bugfix — dbmanager nunca invocado | alto |
| eval-006 | Contratos | Formato de director_report con campos obligatorios | alto |
| eval-007 | Contratos | Sufijos `.audit` y `.qa` en Fase 3 paralela | alto |
| eval-008 | Contratos | Rechazo estructurado de auditor con rejection_details | crítico |
| eval-009 | Contratos | Rechazo estructurado de qa con missing_cases | crítico |
| eval-010 | Reintentos | Reintento con previous_output y rejection_reason completos | alto |
| eval-011 | Reintentos | Escalación a human tras 2 rechazos consecutivos | crítico |
| eval-012 | Reintentos | devops rechaza sin los tres veredictos | crítico |
| eval-013 | Memoria | Curación parcial post-devops invocada y correcta | medio |
| eval-014 | Memoria | Curación completa al cierre con entradas en memoria_global | medio |
| eval-015 | Memoria | Agentes leen memoria antes de actuar | alto |
| eval-016 | Coordinación | Orchestrator NO avanza con solo un veredicto | crítico |
| eval-017 | Coordinación | Orchestrator SÍ avanza con triple aprobación | alto |
| eval-018 | Coordinación | (no documentada en el extracto disponible) | — |
| eval-019 | Coordinación | (no documentada en el extracto disponible) | — |
| eval-020 | Coordinación | (no documentada en el extracto disponible) | — |

### Pendientes y próximos pasos

1. **Construir runner end-to-end** que permita invocar agentes y capturar `director_report`
2. **Ejecutar eval-001 a eval-017** para obtener el primer PRE_CHANGE_SCORE válido
3. **Resolver los 2 hallazgos estructurales abiertos** (ver sección 13)
4. **Hacer commit** de todos los cambios acumulados en el working tree

---

## 13. Historial de versiones

| Versión | Fecha | Cambios principales |
|---|---|---|
| v1.0 | 2026-04-07 | Sistema base: orchestrator, analyst, backend, frontend, developer, dbmanager, auditor, qa, devops, memory_curator, eval_runner |
| v1.0.1 | 2026-04-07 | Fix routing-fix-v1.0.1: reglas explícitas de cuándo NO invocar dbmanager; score Routing 60%→100%, score general 80%→93% |
| v2.0 | 2026-04-07 | Ciclos reales con NetTask: migración Django Auth, bugfix tachado, auditoría post-migración; entradas en memoria_global consolidadas |
| v2.1 | 2026-04-09 | Delta v2.1: 5 nuevos agentes (skill_installer, researcher, tdd_enforcer, red_team, session_logger); orchestrator reescrito con Fases -1/0a/2a/3-triple/5; contratos endurecidos con verification_cycle, verified_files, verified_digest, branch_name; devops cuádruple condición + index binding + staged-payload digest; APROBAR_SIN_EVAL ligado a eval_authorization_scope completo; session_log.md declarado audit_trail_artifact excluido del digest |
| v2.1 + classifier | 2026-04-09 | Clasificador de complejidad integrado en orchestrator: MODO CONSULTA, MODO RÁPIDO (Fase 2b + Fase 4), MODO COMPLETO (flujo completo); Rules 1/3/4 reestructuradas; tabla de clasificación rápida; escalación de modo durante ejecución |

**2 hallazgos estructurales abiertos (alto — no bloqueantes según QA):**
1. `verified_digest` no tiene receta canónica ni recomputación local obligatoria en auditor/qa/red_team (el consenso puede converger sobre un valor heredado sin prueba determinista)
2. devops no exige que el HEAD local sea exactamente el tip de `context.branch_name` (replay cross-branch via historia local)

---

## 14. Guía de inicio rápido

**Requisitos:** VS Code Insiders con GitHub Copilot Chat habilitado y agentes configurados.

1. **Clona el repositorio de agentes** en `~/.copilot` o donde tengas configurado el workspace de agentes.

2. **Abre el workspace `.copilot`** en VS Code. Los agentes estarán disponibles en el panel de Copilot Chat.

3. **Activa el orchestrator** seleccionando el agente `orchestrator` en el chat (modo `orchestrator`).

4. **Describe tu tarea en lenguaje natural.** El orchestrator la clasificará automáticamente: si es una pregunta, responde directamente; si es un cambio pequeño, usa el flujo mínimo; si es una feature, usa el flujo completo.

5. **Para tareas de implementación**, el orchestrator generará un plan antes de ejecutar. Revisa el plan y confirma si hay ambigüedad.

6. **El flujo es automático:** skill_installer detecta el stack, researcher mapea el código afectado, tdd_enforcer escribe tests, los implementadores escriben código, y auditor/qa/red_team verifican en paralelo.

7. **Si hay un rechazo**, el orchestrator lo gestiona automáticamente con hasta 2 reintentos. Si el problema persiste, te pedirá instrucciones.

8. **Los commits los hace devops** solo cuando los tres agentes de verificación aprueban. Nunca hay un commit sin triple aprobación.

9. **Al terminar la sesión**, el orchestrator invoca `memory_curator` en modo completo para consolidar las lecciones aprendidas en `memoria_global.md`.

10. **Consulta `memoria_global.md`** antes de empezar una sesión nueva para ver decisiones de arquitectura previas, antipatrones documentados y buenas prácticas validadas del proyecto.

---

*Generado automáticamente el 9 de abril de 2026 por analyst (GitHub Copilot / Claude Sonnet 4.6)*
