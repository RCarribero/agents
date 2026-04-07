# Eval Report — 2026-04-07 15:00:00 — v1.0.0-baseline

## Resumen

| Métrica | Valor |
|---------|-------|
| **Total evals** | 15 |
| **PASS** | 12 |
| **FAIL** | 2 |
| **PARTIAL** | 1 |
| **Score** | 80% |
| **Fallos críticos** | 0 |

---

## Estado general

✅ **OK:** No se detectaron fallos críticos. El sistema puede avanzar a QA completo.

ℹ️ **PRIMERA EJECUCIÓN:** Esta es la primera versión (baseline) del sistema de evaluaciones. No hay versiones anteriores para comparar tendencias.

---

## Fallos críticos

✅ No se detectaron fallos críticos.

---

## Fallos no críticos

Los siguientes fallos tienen peso **alto** pero no bloquean deploy:

### eval-002 — Tarea solo backend

**Resultado:** FAIL (2/3 criterios cumplidos)

**Descripción:** El orchestrator debe identificar que una tarea puramente de lógica/API solo necesita backend, sin involucrar dbmanager.

**Campo/regla violada:** dbmanager invocado cuando no debería aparecer en el plan

**Output real:**
```
**Fase 1 — Diseño de datos**
  1. **[dbmanager]** → Análisis y optimización de esquema
     - Verificar existencia de tabla `users`/`usuarios` y columna `email`
     - Evaluar necesidad de índice en columna `email` para optimización de búsquedas
```

**Expected:**
```json
{
  "agentes_invocados": ["backend"],
  "agentes_omitidos": ["dbmanager", "frontend"]
}
```

**Impacto:** El orchestrator tiende a sobre-invocar dbmanager en tareas que no requieren cambios de esquema. Esto puede ralentizar el flujo de trabajo y añadir complejidad innecesaria.

**Recomendación:** Refinar las reglas del orchestrator para distinguir entre:
- Tareas que requieren cambio de esquema (CREATE TABLE, ALTER TABLE, ADD COLUMN)
- Tareas que solo consultan datos existentes (SELECT, búsquedas, filtros)

Solo invocar dbmanager para el primer caso.

---

### eval-005 — Tarea de bugfix

**Resultado:** FAIL (2/3 criterios cumplidos)

**Descripción:** Un bugfix debe ir directamente a developer o backend, sin pasar por dbmanager.

**Campo/regla violada:** dbmanager invocado en un bugfix simple

**Output real:**
```
**Fase 1 — Diseño de datos**
  1. **[dbmanager]** → Verificar y ajustar esquema de BD
     - Verificar si hay índice/constraint unique case-sensitive
     - Diseñar migración para agregar índice funcional LOWER(email) si aplica
```

**Expected:**
```json
{
  "tipo": "bugfix",
  "agentes_invocados": ["developer"],
  "agentes_omitidos": ["dbmanager"]
}
```

**Impacto:** El orchestrator trata bugfixes como si fueran features completas, involucrando análisis de esquema cuando la corrección debería ser localizada en código de aplicación (normalización de email antes de búsqueda).

**Recomendación:** Añadir lógica de clasificación de tareas:
- Si la tarea contiene palabras clave "falla", "bug", "error", "rompe" → clasificar como bugfix
- Los bugfixes deben tener un flujo simplificado: developer/backend → auditor ∥ qa → devops
- Solo escalar a dbmanager si el bugfix requiere explútamente rollback de migración o hot-fix de datos

---

## Resultados PARTIAL

Las siguientes evals terminaron en estado **PARTIAL** (cumplimiento parcial de criterios):

### eval-007 — Sufijos en paralelo

**Criterios cumplidos:** 2/4

**Detalle:**
- task_id del auditor termina exactamente en .audit: ✅ Cumplido (task-20260406-001.audit)
- task_id del qa termina exactamente en .qa: ✅ Cumplido (task-20260406-001.qa)
- orchestrator espera ambos reports antes de avanzar a Fase 4: ❌ No verificado (requiere flujo completo)
- Ningún agente avanza sin los dos veredictos: ❌ No verificado (requiere flujo completo)

**Razón del estado parcial:** La evaluación solo pudo verificar que auditor y qa generan los task_ids con los sufijos correctos (.audit y .qa), pero no se ejecutó un flujo completo de orquestación para verificar que el orchestrator efectivamente espera ambos veredictos antes de proceder a la Fase 4. Esta verificación requeriría un sistema de ejecución de flujo completo que no está disponible en el contexto de evaluación actual.

---

## Detalles por grupo

### Routing (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-001 | Tarea solo UI | PASS | alto |
| eval-002 | Tarea solo backend | FAIL | alto |
| eval-003 | Tarea con esquema | PASS | alto |
| eval-004 | Tarea ambigua | PASS | medio |
| eval-005 | Tarea de bugfix | FAIL | alto |

**Score del grupo:** 60%

**Análisis:** El orchestrator maneja correctamente tareas con dependencias claras (UI pura, cambios de esquema, tareas ambiguas), pero sobre-invoca a dbmanager en casos donde no es necesario. Esto sugiere que la lógica de routing necesita refinamiento para distinguir entre:
- Cambios de esquema reales (requieren dbmanager)
- Optimizaciones o consultas sobre esquema existente (no requieren dbmanager)
- Bugfixes simples (no requieren dbmanager)

---

### Contratos (4 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-006 | Formato de director_report | PASS | alto |
| eval-007 | Sufijos en paralelo | PARTIAL | alto |
| eval-008 | Rechazo estructurado de auditor | PASS | crítico |
| eval-009 | Rechazo estructurado de qa | PASS | crítico |

**Score del grupo:** 75%

**Análisis:** Los agentes cumplen correctamente con los formatos de director_report, incluyendo campos obligatorios y estructuras de rechazo. Los agentes auditor y qa emiten rechazos bien estructurados con detalles completos. La eval parcial (eval-007) se debe a limitaciones de la infraestructura de evaluación, no a un fallo del sistema.

---

### Reintentos (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-010 | Reintento con contexto enriquecido | PASS | alto |
| eval-011 | Escalación correcta | PASS | crítico |
| eval-012 | Rechazo de devops sin doble aprobación | PASS | crítico |

**Score del grupo:** 100%

**Análisis:** El sistema de reintentos funciona perfectamente. Los agentes propagan correctamente el contexto de rechazos previos (retry_count, previous_output, rejection_reason), escalan a human tras 2 intentos fallidos, y devops rechaza correctamente cuando no tiene doble aprobación. Este es el grupo con mejor rendimiento.

---

### Memoria (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-013 | Curación parcial post-devops | PASS | medio |
| eval-014 | Curación completa al cierre | PASS | medio |
| eval-015 | Lectura de memoria antes de actuar | PASS | alto |

**Score del grupo:** 100%

**Análisis:** El sistema de memoria funciona correctamente. memory_curator realiza curación parcial y completa según el contexto, respeta los límites de notas por agente (máximo 10), y los agentes consultan y aplican patrones documentados en memoria_global.md antes de implementar.

---

## Tendencia histórica

Comparación de scores de las últimas versiones:

| Versión | Score | Críticos | Fecha |
|---------|-------|----------|-------|
| v1.0.0-baseline | 80% | 0 | 2026-04-07 |

### Análisis de tendencia

ℹ️ **BASELINE:** Esta es la primera versión evaluada. No hay datos históricos para comparación. Los scores futuros se compararán contra este baseline de 80%.

**Recomendaciones para próximas versiones:**
1. Priorizar corrección de eval-002 y eval-005 (routing de dbmanager)
2. Mantener el score de 100% en grupos de Reintentos y Memoria
3. Implementar infraestructura de flujo completo para resolver eval-007

---

## Evals que pasaron

Las siguientes evals pasaron exitosamente:

- **eval-001** — Tarea solo UI (alto)
- **eval-003** — Tarea con esquema (alto)
- **eval-004** — Tarea ambigua (medio)
- **eval-006** — Formato de director_report (alto)
- **eval-008** — Rechazo estructurado de auditor (crítico)
- **eval-009** — Rechazo estructurado de qa (crítico)
- **eval-010** — Reintento con contexto enriquecido (alto)
- **eval-011** — Escalación correcta (crítico)
- **eval-012** — Rechazo de devops sin doble aprobación (crítico)
- **eval-013** — Curación parcial post-devops (medio)
- **eval-014** — Curación completa al cierre (medio)
- **eval-015** — Lectura de memoria antes de actuar (alto)

---

## Conclusiones y próximos pasos

### Fortalezas del sistema

✅ **Reintentos y escalación** (100%): El sistema maneja correctamente los fallos, propaga contexto entre reintentos y escala apropiadamente tras 2 rechazos.

✅ **Memoria** (100%): Los agentes consultan y aplican patrones documentados, y memory_curator mantiene la memoria limpia y actualizada.

✅ **Contratos críticos** (100%): Los agentes auditor, qa y devops cumplen estrictamente con sus formatos de rechazo y aprobación.

### Áreas de mejora

⚠️ **Routing del orchestrator** (60%): Necesita refinamiento para evitar sobre-invocación de dbmanager en:
- Tareas de consulta/búsqueda sin cambio de esquema
- Bugfixes simples de lógica de aplicación

### Acciones recomendadas

1. **ALTA PRIORIDAD:** Refinar lógica de routing del orchestrator (afecta eval-002 y eval-005)
   - Añadir clasificación de tipo de tarea (feature, bugfix, optimización)
   - Crear reglas específicas para cuando SÍ invocar dbmanager:
     - Palabras clave: "añadir campo", "crear tabla", "migración", "cambio de esquema"
     - Palabras clave para NO invocar: "buscar", "consultar", "listar", "filtrar", "bug", "falla"

2. **MEDIA PRIORIDAD:** Implementar infraestructura de flujo completo para eval-007
   - Actualmente solo se verifican formatos individuales
   - Necesario para verificar coordinación del orchestrator

3. **MANTENER:** Grupos de Reintentos y Memoria
   - No requieren cambios, funcionan correctamente

### Criterio de éxito para próxima versión

Para considerar la próxima versión como mejora:
- Score general ≥ 85% (actual: 80%)
- Score grupo Routing ≥ 80% (actual: 60%)
- Mantener 0 fallos críticos
- Resolver eval-002 y eval-005

---

**Versión del informe:** 1.0  
**Evaluador:** eval_runner  
**Duración total de ejecución:** ~25 minutos (15 evals)
