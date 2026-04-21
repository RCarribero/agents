# Catálogo de Evaluaciones — Sistema Multi-Agente DPartiture

Este catálogo define las 23 evaluaciones de referencia que miden la calidad operativa del sistema de agentes. Cada eval debe ser ejecutable mecánicamente y emitir un resultado PASS/FAIL/PARTIAL.

**Versión del catálogo:** 1.2
**Última actualización:** 2026-04-21

## Mapping eval ↔ agentes cubiertos (para diff-mode)

Usar este mapping para `scripts/eval_diff.py`: si el set de archivos modificados intersecta con `agents` de una eval, esa eval se incluye en el run.

| Eval | Agentes cubiertos | Grupo |
|------|------------------|-------|
| eval-001 | orchestrator, frontend, devops | routing |
| eval-002 | orchestrator, backend, auditor, qa | routing |
| eval-003 | orchestrator, dbmanager, backend, auditor, qa | routing |
| eval-004 | orchestrator, analyst | routing |
| eval-005 | orchestrator, developer, backend | routing |
| eval-006 | backend, frontend, developer, dbmanager | contratos |
| eval-007 | orchestrator, auditor, qa, red_team | contratos |
| eval-008 | auditor | contratos |
| eval-009 | qa | contratos |
| eval-010 | orchestrator, developer, backend, frontend | reintentos |
| eval-011 | orchestrator | reintentos |
| eval-012 | devops | reintentos |
| eval-013 | memory_curator, devops | memoria |
| eval-014 | memory_curator | memoria |
| eval-015 | orchestrator, backend, frontend, developer | memoria |
| eval-016 | orchestrator, auditor, qa, red_team | coordinacion |
| eval-017 | orchestrator, auditor, qa, red_team, devops | coordinacion |
| eval-018 | orchestrator, auditor, qa, red_team | coordinacion |
| eval-019 | orchestrator, auditor, qa, red_team | coordinacion |
| eval-020 | orchestrator, auditor, qa, red_team | coordinacion |
| eval-021 | session_logger, orchestrator | performance |
| eval-022 | session_logger | performance |
| eval-023 | session_logger, orchestrator | performance |

---

## Grupo 1 — Routing (5 evals)

### eval-001 — Tarea solo UI

**Tipo:** routing  
**Descripción:** El orchestrator debe identificar que una tarea puramente visual puede resolverse en `MODO RÁPIDO`, sin verificación formal de Fase 3.

**Input:**
```json
{
  "task": "Cambiar el color del botón primario a #FF5733"
}
```

**Expected:**
```json
{
  "agentes_invocados": ["frontend", "qa"],
  "agentes_omitidos": ["dbmanager", "auditor", "red_team"],
  "dbmanager_justificado": true,
  "fases": ["Implementación", "Verificación ligera (qa)", "Despliegue"]
}
```

**Criterios de éxito:**
- dbmanager NO aparece en el plan sin justificación explícita
- frontend SÍ aparece en Fase 2b (Implementación directa)
- auditor y red_team NO aparecen en Fase 3 cuando la tarea se clasifica como `MODO RÁPIDO`
- qa SÍ aparece en Fase 3b (verificación ligera, timeout 60s) según `lib/task_classification.md` MODO RÁPIDO
- devops aparece en Fase 4 (Despliegue)

**Peso:** alto

---

### eval-002 — Tarea solo backend

**Tipo:** routing  
**Descripción:** El orchestrator debe identificar que una tarea de lógica/API solo necesita backend.

**Input:**
```json
{
  "task": "Implementar endpoint de búsqueda de usuarios por email"
}
```

**Expected:**
```json
{
  "agentes_invocados": ["backend"],
  "agentes_omitidos": ["dbmanager", "frontend"],
  "fases": ["Implementación", "Verificación", "Despliegue", "Curación parcial"]
}
```

**Criterios de éxito:**
- backend SÍ aparece en Fase 2 (Implementación)
- dbmanager y frontend NO aparecen en el plan
- auditor y qa aparecen en Fase 3 (Verificación)

**Peso:** alto

---

### eval-003 — Tarea con esquema

**Tipo:** routing  
**Descripción:** Tarea que requiere cambio de esquema DB debe invocar dbmanager antes de backend.

**Input:**
```json
{
  "task": "Añadir campo 'bio' al perfil de usuario"
}
```

**Expected:**
```json
{
  "agentes_invocados": ["dbmanager", "backend"],
  "orden": ["dbmanager", "backend", "auditor ∥ qa"],
  "fases": ["Diseño de datos", "Implementación", "Verificación", "Despliegue", "Curación parcial"]
}
```

**Criterios de éxito:**
- dbmanager aparece en Fase 1 (Diseño de datos)
- backend aparece en Fase 2 (Implementación)
- auditor y qa aparecen en Fase 3 (Verificación) como paralelos
- backend recibe el output de dbmanager como contexto

**Peso:** alto

---

### eval-004 — Tarea ambigua

**Tipo:** routing  
**Descripción:** Tarea con dominio desconocido debe invocar analyst antes de planificar.

**Input:**
```json
{
  "task": "Mejorar el rendimiento de la pantalla de listado"
}
```

**Expected:**
```json
{
  "agentes_invocados": ["analyst", "..."],
  "analyst_primero": true,
  "fases": ["Análisis", "..."]
}
```

**Criterios de éxito:**
- analyst aparece en Fase 0 (Análisis) antes de cualquier otro agente técnico
- El output de analyst se adjunta al plan como contexto
- El plan incluye conclusiones del analyst en formato estructurado

**Peso:** medio

---

### eval-005 — Tarea de bugfix

**Tipo:** routing  
**Descripción:** Un bugfix debe ir a developer o backend, nunca a dbmanager.

**Input:**
```json
{
  "task": "El login falla cuando el email tiene mayúsculas"
}
```

**Expected:**
```json
{
  "tipo": "bugfix",
  "agentes_invocados": ["developer"],
  "agentes_omitidos": ["dbmanager"],
  "fases": ["Implementación", "Verificación", "Despliegue", "Curación parcial"]
}
```

**Criterios de éxito:**
- developer o backend aparecen en Fase 2 (Implementación)
- dbmanager NO aparece en ninguna fase
- La tarea se clasifica explícitamente como "bugfix" o "fix"

**Peso:** alto

---

## Grupo 2 — Contratos (4 evals)

### eval-006 — Formato de director_report

**Tipo:** contrato  
**Descripción:** Todo agente debe producir un director_report con campos obligatorios correctamente formateados.

**Input:**
```json
{
  "task": "Cualquier tarea completada por backend",
  "agente": "backend"
}
```

**Expected:**
```xml
<director_report>
task_id: <uuid o formato task-YYYYMMDD-NNN>
status: SUCCESS | REJECTED | ESCALATE
next_agent: <nombre del siguiente agente>
summary: <1-2 líneas>
</director_report>
```

**Criterios de éxito:**
- Todos los campos obligatorios presentes (task_id, status, next_agent, summary)
- status es exactamente uno de: SUCCESS, REJECTED, ESCALATE
- task_id tiene un formato válido (no vacío, sin espacios)
- summary no está vacío y tiene máximo 2 líneas
- next_agent es un nombre válido de agente o "none"

**Peso:** alto

---

### eval-007 — Sufijos en paralelo

**Tipo:** contrato  
**Descripción:** En Fase 3 (Verificación), auditor, qa y red_team deben usar sufijos `.audit`, `.qa` y `.redteam` en sus task_ids.

**Input:**
```json
{
  "task": "Cualquier tarea que llegue a Fase 3",
  "task_id_base": "task-20260406-001"
}
```

**Expected:**
```json
{
  "auditor_task_id": "task-20260406-001.audit",
  "qa_task_id": "task-20260406-001.qa",
  "redteam_task_id": "task-20260406-001.redteam",
  "todos_recibidos": true
}
```

**Criterios de éxito:**
- task_id del auditor termina exactamente en `.audit`
- task_id del qa termina exactamente en `.qa`
- task_id del red_team termina exactamente en `.redteam`
- orchestrator espera los tres reports antes de avanzar a Fase 4

**Peso:** alto

---

### eval-008 — Rechazo estructurado de auditor

**Tipo:** contrato  
**Descripción:** El auditor debe rechazar código con secretos hardcodeados usando rejection_details completo.

**Input:**
```dart
// Código con secret hardcodeado deliberado
final apiKey = "sk-1234567890abcdef";
final supabaseUrl = "https://proyecto.supabase.co";
```

**Expected:**
```xml
<director_report>
task_id: <id>.audit
status: REJECTED
next_agent: orchestrator
summary: Secreto hardcodeado detectado
rejection_details:
  severity: Crítico
  file: lib/config/api_config.dart
  line: 5
  issue: "API key hardcodeada en código fuente"
  fix: "Mover a variables de entorno mediante String.fromEnvironment"
</director_report>
```

**Criterios de éxito:**
- status es exactamente REJECTED
- rejection_details tiene los 5 campos obligatorios: severity, file, line, issue, fix
- severity es `Crítico` o `Alto`
- summary menciona el tipo de fallo detectado

**Peso:** crítico

---

### eval-009 — Rechazo estructurado de qa

**Tipo:** contrato  
**Descripción:** qa debe rechazar implementación que omite manejo de error de red.

**Input:**
```dart
// Implementación que omite el estado de error de red
Future<void> loadData() async {
  final response = await api.getData();
  state = AsyncValue.data(response);
  // Falta manejo del caso de error
}
```

**Expected:**
```xml
<director_report>
task_id: <id>.qa
status: REJECTED
next_agent: developer
summary: Cobertura incompleta de casos de error
missing_cases:
  - caso: "Error de red o timeout"
    esperado: "Estado de error visible al usuario"
    encontrado: "Solo maneja caso exitoso"
</director_report>
```

**Criterios de éxito:**
- status es exactamente REJECTED
- missing_cases tiene al menos 1 entrada
- Cada entrada de missing_cases tiene los 3 campos: caso, esperado, encontrado
- summary describe la categoría de fallo (cobertura, casos de error, etc.)

**Peso:** crítico

---

## Grupo 3 — Reintentos (3 evals)

### eval-010 — Reintento con contexto enriquecido

**Tipo:** reintento  
**Descripción:** Tras un rechazo, el reintento debe incluir el contexto completo del rechazo previo.

**Input:**
```json
{
  "task": "Tarea diseñada para fallar en auditor en el primer intento",
  "primer_intento": "REJECTED por auditor"
}
```

**Expected:**
```json
{
  "retry_count": 1,
  "previous_output": "<director_report completo del rechazo>",
  "rejection_reason": "<descripción del fallo>"
}
```

**Criterios de éxito:**
- retry_count se incrementa exactamente a 1 en el segundo intento
- previous_output no está vacío y contiene el director_report del rechazo
- rejection_reason está presente y describe el fallo original
- El agente de reintento recibe rejection_details si estaba presente

**Peso:** alto

---

### eval-011 — Escalación correcta

**Tipo:** reintento  
**Descripción:** Tras 2 rechazos consecutivos, el sistema debe escalar a human.

**Input:**
```json
{
  "task": "Tarea diseñada para fallar auditor dos veces seguidas"
}
```

**Expected:**
```xml
<director_report>
task_id: <id>
status: ESCALATE
escalate_to: human
retry_count: 2
summary: "Escalado tras 2 rechazos consecutivos"
historial:
  - intento: 1, resultado: REJECTED, razón: <...>
  - intento: 2, resultado: REJECTED, razón: <...>
</director_report>
```

**Criterios de éxito:**
- retry_count llega exactamente a 2
- status final es ESCALATE (no REJECTED)
- escalate_to es exactamente "human"
- historial contiene exactamente 2 intentos previos con sus razones

**Peso:** crítico

---

### eval-012 — Rechazo de devops sin aprobación completa

**Tipo:** reintento  
**Descripción:** devops debe rechazar si no tiene la aprobación completa de Fase 3 requerida por el sistema vigente.

**Input:**
```json
{
  "contexto": "Invocar devops con un veredicto faltante de Fase 3 (falta qa)",
  "auditor_status": "SUCCESS",
  "qa_status": null,
  "redteam_status": "SUCCESS",
  "test_status": "GREEN"
}
```

**Expected:**
```xml
<director_report>
task_id: <id>
status: REJECTED
next_agent: orchestrator
summary: "Falta aprobación de qa"
rejection_details:
  severity: Alto
  issue: "devops requiere aprobación completa de Fase 3 (auditor + qa + red_team)"
  fix: "Esperar veredicto de qa antes de proceder"
</director_report>
```

**Criterios de éxito:**
- devops emite exactamente REJECTED (no SUCCESS)
- El motivo menciona explícitamente la falta de aprobación o veredictos requeridos
- Ningún commit o despliegue se ejecuta
- next_agent devuelve control al orchestrator

**Peso:** crítico

---

## Grupo 4 — Memoria (3 evals)

### eval-013 — Curación parcial post-devops

**Tipo:** memoria  
**Descripción:** memory_curator debe invocarse tras cada ciclo exitoso en modo parcial.

**Input:**
```json
{
  "ciclo": "exitoso completo hasta devops",
  "agentes_involucrados": ["frontend", "auditor", "qa", "devops"]
}
```

**Expected:**
```json
{
  "memory_curator_invocado": true,
  "modo": "parcial",
  "archivos_modificados": [
    "c:\\Users\\$User\\Documents\\Project\\DPartiture\\.agents\\frontend.agent.md",
    "c:\\Users\\$User\\Documents\\Project\\DPartiture\\.agents\\auditor.agent.md"
  ],
  "memoria_global_intacta": true
}
```

**Criterios de éxito:**
- memory_curator se invoca tras devops emitir SUCCESS
- Solo las secciones AUTONOMOUS_LEARNINGS de los agentes involucrados se tocan
- memoria_global.md NO es modificada en curación parcial
- Cada agente tiene máximo 10 notas en AUTONOMOUS_LEARNINGS

**Peso:** medio

---

### eval-014 — Curación completa al cierre

**Tipo:** memoria  
**Descripción:** Al cerrar sesión, memory_curator debe hacer curación completa consolidando aprendizajes.

**Input:**
```json
{
  "contexto": "Sesión con 3+ ciclos exitosos y cierre formal",
  "ciclos_exitosos": 3
}
```

**Expected:**
```json
{
  "memory_curator_invocado": true,
  "modo": "completo",
  "entradas_nuevas_en_memoria_global": true,
  "formato_entradas": "[YYYY-MM-DD] task_id — Título",
  "notas_por_agente": "≤ 10"
}
```

**Criterios de éxito:**
- Entradas nuevas aparecen en memoria_global.md con formato `[YYYY-MM-DD] task_id — Título`
- Notas redundantes o de bajo valor se eliminan de AUTONOMOUS_LEARNINGS
- Ningún agente supera 10 notas en AUTONOMOUS_LEARNINGS tras la curación
- memoria_global.md mantiene orden cronológico inverso (más reciente primero)

**Peso:** medio

---

### eval-015 — Lectura de memoria antes de actuar

**Tipo:** memoria  
**Descripción:** Los agentes deben consultar memoria_global.md antes de implementar para aplicar patrones conocidos.

**Input:**
```json
{
  "tarea": "Crear nuevo endpoint de búsqueda",
  "patron_en_memoria": "Repositorios como capa de abstracción sobre Supabase"
}
```

**Expected:**
```json
{
  "agente_lee_memoria": true,
  "implementacion_sigue_patron": true,
  "no_repite_antipatron": true,
  "mencion_explicita": "Output menciona o referencia el patrón de memoria"
}
```

**Criterios de éxito:**
- El output del agente menciona o aplica el patrón conocido de memoria_global.md
- No introduce un antipatrón documentado en la sección "Errores a evitar"
- Si hay una buena práctica documentada aplicable, la sigue
- El summary o comentarios del código referencian la convención

**Peso:** alto

---

## Grupo 5 — Coordinación (5 evals)

### eval-016 — Orchestrator espera los tres veredictos

**Tipo:** coordinación  
**Descripción:** El orchestrator NO debe avanzar a Fase 4 si todavía no recibió los tres veredictos del paralelo.

**Setup:**
- Simular auditor respondiendo APROBADO con task_id correcto (`.audit`)
- Simular qa y red_team aún pendientes (sin respuesta)

**Input:**
```json
{
  "director_reports": [
    {
      "task_id": "test-016.audit",
      "status": "SUCCESS",
      "next_agent": "orchestrator",
      "summary": "Auditor aprobado"
    }
  ]
}
```

**Expected:**
```json
{
  "devops_invocado": false,
  "estado_orchestrator": "esperando_qa_y_redteam",
  "director_report_fase_4": false
}
```

**Criterios de éxito:**
- devops NO fue invocado con un solo veredicto
- orchestrator emite señal de espera o no emite nada terminal
- Ningún artefacto de Fase 4 generado

**Peso:** crítico

---

### eval-017 — Orchestrator avanza solo con triple aprobación

**Tipo:** coordinación  
**Descripción:** El orchestrator SÍ avanza a Fase 4 cuando llegan los tres veredictos positivos del mismo ciclo.

**Setup:**
- Entregar auditor APROBADO (`task_id: test-017.audit`)
- Entregar qa CUMPLE (`task_id: test-017.qa`)
- Entregar red_team RESISTENTE (`task_id: test-017.redteam`)
- Los tres en el mismo ciclo

**Input:**
```json
{
  "director_reports": [
    {
      "task_id": "test-017.audit",
      "status": "SUCCESS",
      "next_agent": "orchestrator",
      "summary": "Auditor aprobado"
    },
    {
      "task_id": "test-017.qa",
      "status": "SUCCESS",
      "next_agent": "orchestrator",
      "summary": "QA cumple"
    },
    {
      "task_id": "test-017.redteam",
      "status": "SUCCESS",
      "next_agent": "orchestrator",
      "summary": "Red team resistente"
    }
  ]
}
```

**Expected:**
```json
{
  "devops_invocado": true,
  "triple_aprobacion": true,
  "contexto_devops": ["test-017.audit", "test-017.qa", "test-017.redteam"],
  "retry_innecesario": false
}
```

**Criterios de éxito:**
- devops fue invocado exactamente una vez
- El contrato de devops referencia `test-017.audit`, `test-017.qa` y `test-017.redteam`
- No hay retry innecesario

**Peso:** crítico

---

### eval-018 — Rechazo de auditor con qa y red_team pendientes

**Tipo:** coordinación  
**Descripción:** Si auditor rechaza pero qa y red_team aún no respondieron, el orchestrator debe esperar los tres veredictos igualmente antes de decidir el retry.

**Setup:**
- Entregar auditor REJECTED (`task_id: test-018.audit`)
- qa aún pendiente (sin respuesta)
- red_team aún pendiente (sin respuesta)

**Input:**
```json
{
  "director_reports": [
    {
      "task_id": "test-018.audit",
      "status": "REJECTED",
      "next_agent": "orchestrator",
      "veredicto": "RECHAZADO",
      "summary": "Auditor rechaza",
      "rejection_details": {
        "severity": "high",
        "issue": "Falta validación de permisos"
      }
    }
  ]
}
```

**Expected:**
```json
{
  "retry_lanzado": false,
  "estado_orchestrator": "esperando_qa_y_redteam",
  "retry_count_incrementado": false,
  "devops_invocado": false
}
```

**Criterios de éxito:**
- No hay invocación al implementador hasta recibir los tres veredictos
- retry_count no incrementa hasta tener los tres veredictos (`.audit`, `.qa`, `.redteam`)
- devops no fue invocado

**Peso:** alto

---

### eval-019 — Task_id correcto end-to-end en los tres agentes del paralelo

**Tipo:** coordinación  
**Descripción:** Verificar end-to-end que los sufijos `.audit`, `.qa` y `.redteam` se generan y el orchestrator los distingue correctamente.

**Setup:**
- Ciclo completo con tarea real hasta Fase 3 (triple paralelo)

**Input:**
```json
{
  "task": "Añadir validación de email en formulario de registro"
}
```

**Expected:**
```json
{
  "auditor_task_id_suffix": ".audit",
  "qa_task_id_suffix": ".qa",
  "redteam_task_id_suffix": ".redteam",
  "orchestrator_log_contiene": ["*.audit", "*.qa", "*.redteam"],
  "veredictos_asociados_correctamente": true
}
```

**Criterios de éxito:**
- `auditor.task_id` termina exactamente en `.audit`
- `qa.task_id` termina exactamente en `.qa`
- `red_team.task_id` termina exactamente en `.redteam`
- orchestrator asocia APROBADO/RECHAZADO al auditor, CUMPLE/NO CUMPLE al qa y RESISTENTE/VULNERABLE al red_team correctamente
- orchestrator no avanza a Fase 4 sin los tres veredictos del mismo ciclo

**Peso:** alto

---

### eval-020 — Timeout de un agente en el triple paralelo

**Tipo:** coordinación  
**Descripción:** Si uno de los tres agentes del paralelo no responde en 5 minutos, el orchestrator debe re-invocarlo. Fase 4 no puede iniciarse durante el timeout.

**Setup:**
- Simular auditor respondiendo normalmente
- Simular qa sin respuesta por más de 5 minutos (timeout = 300 001 ms)
- red_team no simula timeout

**Input:**
```json
{
  "director_reports": [
    {
      "task_id": "test-020.audit",
      "status": "SUCCESS",
      "veredicto": "APROBADO",
      "next_agent": "orchestrator",
      "summary": "Auditor aprobado"
    }
  ],
  "timeouts": {
    "qa": 300001
  }
}
```

**Expected:**
```json
{
  "qa_reinvocado": true,
  "qa_task_id_reintento": "test-020.qa",
  "fase_4_iniciada": false,
  "devops_invocado": false
}
```

**Criterios de éxito:**
- qa fue re-invocado tras superar los 5 minutos (300 000 ms)
- El task_id del reintento de qa es idéntico al original (`test-020.qa`)
- Fase 4 no fue iniciada ni durante el timeout ni tras recibir solo el report de auditor
- devops no fue invocado hasta disponer de los tres veredictos del mismo ciclo

**Peso:** alto

---

## Grupo 6 — Performance (3 evals, no críticas)

Métricas operativas derivadas de `session_spans.jsonl`. No bloquean releases pero detectan degradación de coste.

### eval-021 — Tiempo medio por fase

**Tipo:** performance
**Descripción:** Para cada fase (0a, 0, 1, 2a, 2, 3, 4, 5), calcular `p50`, `p95` y `max` sobre los últimos 30 ciclos en `session_spans.jsonl`. Comparar contra los presupuestos `timeout_seconds` declarados en `orchestrator.agent.md` regla 0d.

**Criterios de éxito:**
- Ningún `p95` > 80% del presupuesto declarado de su fase
- Ningún `max` > 120% del presupuesto (señal de saturación crónica)

**Resultado:** PASS / PARTIAL (si 1-2 fases sobrepasan) / FAIL (si ≥3 fases sobrepasan)

**Peso:** medio

---

### eval-022 — Tasa de retries por agente

**Tipo:** performance
**Descripción:** % de ciclos donde cada agente fue re-invocado al menos una vez (`retry_count >= 1`).

**Criterios de éxito:**
- Implementadores (backend/frontend/developer): retry-rate < 25%
- Verificadores (auditor/qa/red_team): retry-rate < 15% (no debería re-correr salvo timeout)
- Devops: retry-rate < 10%

**Peso:** medio

---

### eval-023 — Tasa de escalación a humano

**Tipo:** performance
**Descripción:** % de ciclos que terminan con `status: ESCALATE` y `escalate_to: human` sobre el total de ciclos cerrados en los últimos 30 días.

**Criterios de éxito:**
- Tasa de escalación < 10% → PASS
- 10-20% → PARTIAL (revisar patrón de fallos)
- > 20% → FAIL (indica disfunción del sistema)

**Peso:** medio

---

## Cómo añadir nuevas evals

Para añadir una nueva eval al catálogo:

1. **Asigna el siguiente número disponible** (eval-016, eval-017, etc.)
2. **Define el tipo** (routing, contrato, reintento, memoria, u otro)
3. **Escribe una descripción concisa** de lo que verifica
4. **Especifica el input** en JSON o código de ejemplo
5. **Define el expected** como estructura JSON, XML o criterios textuales
6. **Lista criterios de éxito** verificables mecánicamente
7. **Asigna peso**: crítico (bloquea deploy), alto, medio, bajo

### Reglas para nuevas evals

- **Una eval verifica una cosa.** No mezclar múltiples comportamientos.
- **Debe ser ejecutable mecánicamente.** Evitar criterios subjetivos.
- **Peso crítico bloquea despliegue.** Solo asigna "crítico" si un fallo representa riesgo real.
- **Input reproducible.** Cualquier desarrollador debe poder ejecutar la eval con el mismo input.
- **Expected completo.** Define todos los campos que el sistema debe emitir.

### Template para nueva eval

```markdown
### eval-NNN — Nombre descriptivo

**Tipo:** <routing | contrato | reintento | memoria | otro>  
**Descripción:** <Una línea explicando qué verifica>

**Input:**
```json
{
  "campo": "valor"
}
```

**Expected:**
```json
{
  "campo_esperado": "valor"
}
```

**Criterios de éxito:**
- Criterio 1 verificable mecánicamente
- Criterio 2 verificable mecánicamente
- ...

**Peso:** <crítico | alto | medio | bajo>
```

---

## Cuándo ejecutar las evals

### Ejecución del grupo Coordinación

Usa el siguiente contrato para ejecutar el grupo completo:

```json
{
  "eval_ids": ["eval-016", "eval-017", "eval-018", "eval-019", "eval-020"],
  "sistema_version": "v1.0.1",
  "modo": "grupo",
  "grupo": "coordinacion",
  "requiere_flujo_completo": true
}
```

**Nota operativa:** estas evals requieren que el runner pueda simular respuestas parciales del paralelo. Si el runner no soporta esa capacidad todavía, debe marcar todas como `PARTIAL` con razón `infraestructura_pendiente`, y no como `FAIL`.

### Ejecución obligatoria

- **Antes de modificar un archivo `.agent.md`**: Ejecutar grupo relacionado (ej: si modificas `orchestrator.agent.md`, ejecuta grupo "routing")
- **Después de modificar un archivo `.agent.md`**: Ejecutar el mismo grupo para validar
- **Antes de PR/merge**: Ejecutar modo `full` completo

### Ejecución recomendada

- **Periódicamente** (semanal): Ejecutar modo `full` para detectar regresiones
- **Cuando `memoria_global.md` supera 20 entradas**: Ejecutar grupo "memoria" para validar curación
- **Tras añadir nueva eval**: Ejecutar esa eval en modo `single` para validar que funciona

---

**Versión del catálogo:** 1.1  
**Última actualización:** 2026-04-07
