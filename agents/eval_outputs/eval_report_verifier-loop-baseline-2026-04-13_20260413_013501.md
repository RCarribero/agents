# Eval Report - 2026-04-13 01:35:01 - vverifier-loop-baseline-2026-04-13

## Resumen

| Metrica | Valor |
|---------|-------|
| **Total evals** | 20 |
| **PASS** | 12 |
| **FAIL** | 1 |
| **PARTIAL** | 7 |
| **Score** | 60% |
| **Fallos criticos** | 1 |

---

## Estado general

ATENCION: Se detecto 1 fallo critico. El baseline mantiene la misma deuda critica observada en la ultima corrida full disponible y no muestra regresion de score.

Este baseline se genero por inspeccion contractual y simulacion guiada por catalogo. Refleja el snapshot actual del workspace y no revirtio cambios locales previos fuera de `agents/eval_outputs/`.

---

## Limitaciones relevantes

- Coordinacion: `eval-016`, `eval-018`, `eval-019` y `eval-020` quedaron en `PARTIAL` con razon `infraestructura_pendiente`. El workspace no expone un runner stateful capaz de observar el triple paralelo, estados intermedios y timeouts reales desde `eval_runner`.
- Verificacion: los tiempos de ejecucion quedaron en `0 ms` porque la baseline fue por inspeccion/simulacion, no por ejecucion end-to-end de subagentes.
- Snapshot: el worktree no estaba limpio al iniciar la baseline. Se detectaron cambios locales previos, incluyendo `agents/orchestrator.agent.md`. El reporte describe el estado actual del checkout tal como estaba al momento de evaluar.

---

## Fallos criticos

### eval-017 - Orchestrator avanza solo con doble aprobacion

**Descripcion:** El catalogo espera que el orchestrator habilite Fase 4 con dos veredictos positivos, pero el sistema vigente exige triple aprobacion (`auditor` + `qa` + `red_team`).

**Campo/regla violada:** Regla de coordinacion de Fase 3 vs expectativa del catalogo `eval-017`.

**Output real:**

```text
Fase 3 - Condicion de salida: auditor APROBADO y qa CUMPLE y red_team RESISTENTE
Fase 4 - Despliegue: devops. Solo si Fase 3 da triple aprobacion.
```

**Expected:**

```text
devops_invocado: true
doble_aprobacion: true
contexto_devops: ["test-017.audit", "test-017.qa"]
retry_innecesario: false
```

**Impacto:** Mientras `eval-017` siga modelando doble aprobacion y el contrato real exija triple aprobacion, el gate de evaluacion seguira marcando un FAIL critico aunque el comportamiento actual sea internamente consistente.

**Recomendacion:** Alinear `agents/evals/eval_catalog.md` con la politica vigente de triple aprobacion o introducir compatibilidad explicita si la doble aprobacion sigue siendo el comportamiento deseado.

---

## Fallos no criticos

No se detectaron resultados `FAIL` de peso alto o medio. Las desviaciones restantes quedaron en estado `PARTIAL`.

---

## Resultados PARTIAL

### eval-001 - Tarea solo UI

**Criterios cumplidos:** 3/4

**Detalle:**
- dbmanager NO aparece en el plan sin justificacion explicita: OK - MODO RAPIDO omite dbmanager.
- frontend SI aparece en Fase 2 (Implementacion): OK - se enruta al implementador directo de UI.
- auditor y qa aparecen en Fase 3 (Verificacion) como paralelos: NO - MODO RAPIDO omite Fase 3.
- devops aparece en Fase 4 (Despliegue): OK - el flujo rapido conserva devops.

**Razon del estado parcial:** El catalogo espera verificacion formal incluso para una tarea solo UI, pero el contrato actual usa MODO RAPIDO y omite Fase 3.

---

### eval-008 - Rechazo estructurado de auditor

**Criterios cumplidos:** 3/4

**Detalle:**
- status es exactamente REJECTED: OK.
- rejection_details tiene los 5 campos obligatorios: severity, file, line, issue, fix: OK.
- severity es "critical" o "high": NO - el contrato usa `Critico | Alto | Medio`.
- summary menciona el tipo de fallo detectado: OK.

**Razon del estado parcial:** La estructura existe, pero la taxonomia de severidad no coincide con la esperada por la eval.

---

### eval-012 - Rechazo de devops sin doble aprobacion

**Criterios cumplidos:** 3/4

**Detalle:**
- devops emite exactamente REJECTED (no SUCCESS): OK.
- El motivo menciona explicitamente la falta de aprobacion: OK.
- Ningun commit o despliegue se ejecuta: OK.
- next_agent devuelve control al orchestrator: NO - el contrato fija `session_logger + memory_curator`.

**Razon del estado parcial:** El rechazo es correcto, pero la ruta formal de retorno no coincide con la expectativa del catalogo.

---

### eval-016 - Orchestrator espera ambos veredictos

**Criterios cumplidos:** 3/3

**Detalle:**
- devops NO fue invocado con un solo veredicto: OK.
- orchestrator emite senal de espera o no emite nada terminal: OK.
- Ningun artefacto de Fase 4 generado: OK.

**Razon del estado parcial:** `infraestructura_pendiente` para observar el paralelo en ejecucion real.

---

### eval-018 - Rechazo de auditor con qa y red_team pendientes

**Criterios cumplidos:** 3/3

**Detalle:**
- No hay invocacion al implementador hasta recibir los tres veredictos: OK.
- retry_count no incrementa hasta tener los tres veredictos (`.audit`, `.qa`, `.redteam`): OK.
- devops no fue invocado: OK.

**Razon del estado parcial:** `infraestructura_pendiente` para validar el estado intermedio del orchestrator en tiempo real.

---

### eval-019 - Task_id correcto end-to-end en los tres agentes del paralelo

**Criterios cumplidos:** 5/5

**Detalle:**
- `auditor.task_id` termina exactamente en `.audit`: OK.
- `qa.task_id` termina exactamente en `.qa`: OK.
- `red_team.task_id` termina exactamente en `.redteam`: OK.
- orchestrator asocia veredictos correctamente por rol: OK.
- orchestrator no avanza a Fase 4 sin los tres veredictos del mismo ciclo: OK.

**Razon del estado parcial:** `infraestructura_pendiente` para verificar el flujo end-to-end con runner paralelo real.

---

### eval-020 - Timeout de un agente en el triple paralelo

**Criterios cumplidos:** 4/4

**Detalle:**
- qa fue re-invocado tras superar los 5 minutos (300000 ms): OK.
- El task_id del reintento de qa es identico al original (`test-020.qa`): OK.
- Fase 4 no fue iniciada ni durante el timeout ni tras recibir solo el report de auditor: OK.
- devops no fue invocado hasta disponer de los tres veredictos del mismo ciclo: OK.

**Razon del estado parcial:** `infraestructura_pendiente` para comprobar timeout y reintento en ejecucion efectiva.

---

## Detalles por grupo

### Routing (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-001 | Tarea solo UI | PARTIAL | alto |
| eval-002 | Tarea solo backend | PASS | alto |
| eval-003 | Tarea con esquema | PASS | alto |
| eval-004 | Tarea ambigua | PASS | medio |
| eval-005 | Tarea de bugfix | PASS | alto |

**Score del grupo:** 80%

---

### Contratos (4 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-006 | Formato de director_report | PASS | alto |
| eval-007 | Sufijos en paralelo | PASS | alto |
| eval-008 | Rechazo estructurado de auditor | PARTIAL | critico |
| eval-009 | Rechazo estructurado de qa | PASS | critico |

**Score del grupo:** 75%

---

### Reintentos (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-010 | Reintento con contexto enriquecido | PASS | alto |
| eval-011 | Escalacion correcta | PASS | critico |
| eval-012 | Rechazo de devops sin doble aprobacion | PARTIAL | critico |

**Score del grupo:** 67%

---

### Memoria (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-013 | Curacion parcial post-devops | PASS | medio |
| eval-014 | Curacion completa al cierre | PASS | medio |
| eval-015 | Lectura de memoria antes de actuar | PASS | alto |

**Score del grupo:** 100%

---

### Coordinacion (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-016 | Orchestrator espera ambos veredictos | PARTIAL | critico |
| eval-017 | Orchestrator avanza solo con doble aprobacion | FAIL | critico |
| eval-018 | Rechazo de auditor con qa y red_team pendientes | PARTIAL | alto |
| eval-019 | Task_id correcto end-to-end en los tres agentes del paralelo | PARTIAL | alto |
| eval-020 | Timeout de un agente en el triple paralelo | PARTIAL | alto |

**Score del grupo:** 0%

---

## Tendencia historica

Comparacion de scores de las ultimas versiones relevantes:

| Version | Score | Criticos | Fecha |
|---------|-------|----------|-------|
| verifier-loop-baseline-2026-04-13 | 60% | 1 | 2026-04-13 |
| post-remove-api-2026-04-10 | 60% | 1 | 2026-04-10 |
| pre-remove-api-2026-04-10 | 60% | 1 | 2026-04-10 |

### Analisis de tendencia

ESTABLE: El score se mantiene estable respecto a la ultima version disponible (variacion < 5%).

---

## Evals que pasaron

- **eval-002** - Tarea solo backend (alto)
- **eval-003** - Tarea con esquema (alto)
- **eval-004** - Tarea ambigua (medio)
- **eval-005** - Tarea de bugfix (alto)
- **eval-006** - Formato de director_report (alto)
- **eval-007** - Sufijos en paralelo (alto)
- **eval-009** - Rechazo estructurado de qa (critico)
- **eval-010** - Reintento con contexto enriquecido (alto)
- **eval-011** - Escalacion correcta (critico)
- **eval-013** - Curacion parcial post-devops (medio)
- **eval-014** - Curacion completa al cierre (medio)
- **eval-015** - Lectura de memoria antes de actuar (alto)

---

## Tiempos de ejecucion

| Eval ID | Tiempo (ms) | Timeout |
|---------|-------------|---------|
| eval-001 | 0 | No |
| eval-002 | 0 | No |
| eval-003 | 0 | No |
| eval-004 | 0 | No |
| eval-005 | 0 | No |
| eval-006 | 0 | No |
| eval-007 | 0 | No |
| eval-008 | 0 | No |
| eval-009 | 0 | No |
| eval-010 | 0 | No |
| eval-011 | 0 | No |
| eval-012 | 0 | No |
| eval-013 | 0 | No |
| eval-014 | 0 | No |
| eval-015 | 0 | No |
| eval-016 | 0 | No |
| eval-017 | 0 | No |
| eval-018 | 0 | No |
| eval-019 | 0 | No |
| eval-020 | 0 | No |

**Tiempo total de ejecucion:** 0 ms (0.00 min)

---

## Recomendaciones

### Acciones criticas (requeridas antes de usar este gate como proteccion dura)

1. **Alinear `eval-017` con la politica real de Fase 3** - El catalogo y el contrato discrepan entre doble y triple aprobacion.

### Acciones recomendadas (mejoran la calidad del baseline)

1. **Definir si MODO RAPIDO debe omitir verificacion formal** - Esto resolveria la discrepancia abierta en `eval-001`.
2. **Unificar taxonomia de severidad del auditor** - Alinear `Critico | Alto | Medio` con `critical | high` o adaptar el catalogo de `eval-008`.
3. **Alinear la ruta formal de rechazo de devops** - Resolver la discrepancia de `next_agent` en `eval-012`.
4. **Implementar un runner de coordinacion stateful** - Necesario para convertir `eval-016`, `eval-018`, `eval-019` y `eval-020` de `PARTIAL` a evidencia runtime real.

### Evals a completar

- **eval-001** - discrepancia contractual entre MODO RAPIDO y verificacion formal esperada.
- **eval-008** - taxonomia de severidad no alineada con el catalogo.
- **eval-012** - ruta de retorno de devops no alineada con el catalogo.
- **eval-016** - infraestructura_pendiente para paralelo real.
- **eval-018** - infraestructura_pendiente para paralelo real.
- **eval-019** - infraestructura_pendiente para paralelo real.
- **eval-020** - infraestructura_pendiente para paralelo real.

---

## Metadata del informe

- **Version del sistema:** verifier-loop-baseline-2026-04-13
- **Fecha de ejecucion:** 2026-04-13 01:35:01
- **Modo de ejecucion:** full
- **Grupo ejecutado:** all
- **Eval especifica:** N/A
- **Version del catalogo:** workspace-current
- **Generador:** eval_runner.agent.md

---

## Proximos pasos

1. No usar el resultado como gate de merge limpio hasta resolver la divergencia critica de `eval-017`.
2. Si necesitas evidencia runtime de coordinacion, ejecutar el grupo `coordinacion` en un runner que soporte estados parciales del paralelo.
3. Si necesitas baseline estrictamente pre-cambio contra `HEAD`, repetir la corrida sobre un snapshot limpio o sobre la referencia git deseada.

---

**Fin del informe**