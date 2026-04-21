# Eval Report — 2026-04-16 00:00:00 — vfull

## Resumen

| Métrica | Valor |
|---------|-------|
| **Total evals** | 20 |
| **PASS** | 20 |
| **FAIL** | 0 |
| **PARTIAL** | 0 |
| **Score** | 100% |
| **Fallos críticos** | 0 |

---

## Estado general

✅ **OK:** No se detectaron fallos críticos. El sistema puede avanzar a QA completo.

---

## Fallos críticos

✅ No se detectaron fallos críticos.

---

## Fallos no críticos

✅ No se detectaron fallos no críticos.

---

## Resultados PARTIAL

✅ No hay resultados parciales.

---

## Detalles por grupo

### Routing

Score: **100%**

### Contratos

Score: **100%**

### Reintentos

Score: **100%**

### Memoria

Score: **100%**

### Coordinación

Score: **100%**

---

## Tendencia histórica

| Versión | Score | Críticos | Fecha |
|---------|-------|----------|-------|
| vfull | 100% | 0 | 2026-04-16 |
| v1.0.1 | 93% | 0 | 2026-04-07 |
| v1.0.0 | 80% | 0 | 2026-04-07 |

### Análisis de tendencia

✅ **MEJORA:** 93% -> 100%.# Eval Report — 2026-04-16 00:00:00 — vfull

## Resumen

| Métrica | Valor |
|---------|-------|
| **Total evals** | 20 |
| **PASS** | 20 |
| **FAIL** | 0 |
| **PARTIAL** | 0 |
| **Score** | 100% |
| **Fallos críticos** | 0 |

---

## Estado general

✅ **OK:** No se detectaron fallos críticos. El sistema puede avanzar a QA completo.

---

## Fallos críticos

✅ No se detectaron fallos críticos.

---

## Fallos no críticos

✅ No se detectaron fallos no críticos.

---

## Resultados PARTIAL

✅ No hay resultados parciales.

---

## Detalles por grupo

### Routing (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-001 | Tarea solo UI | PASS | alto |
| eval-002 | Tarea solo backend | PASS | alto |
| eval-003 | Tarea con esquema | PASS | alto |
| eval-004 | Tarea ambigua | PASS | medio |
| eval-005 | Tarea de bugfix | PASS | alto |

**Score del grupo:** 100%

---

### Contratos (4 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-006 | Formato de director_report | PASS | alto |
| eval-007 | Sufijos en paralelo | PASS | alto |
| eval-008 | Rechazo estructurado de auditor | PASS | crítico |
| eval-009 | Rechazo estructurado de qa | PASS | crítico |

**Score del grupo:** 100%

---

### Reintentos (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-010 | Reintento con contexto enriquecido | PASS | alto |
| eval-011 | Escalación correcta | PASS | crítico |
| eval-012 | Rechazo de devops sin aprobación completa | PASS | crítico |

**Score del grupo:** 100%

---

### Memoria (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-013 | Curación parcial post-devops | PASS | medio |
| eval-014 | Curación completa al cierre | PASS | medio |
| eval-015 | Lectura de memoria antes de actuar | PASS | alto |

**Score del grupo:** 100%

---

### Coordinación (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
| eval-016 | Orchestrator espera los tres veredictos | PASS | crítico |
| eval-017 | Orchestrator avanza solo con triple aprobación | PASS | crítico |
| eval-018 | Rechazo de auditor con qa y red_team pendientes | PASS | alto |
| eval-019 | Task_id correcto end-to-end en los tres agentes del paralelo | PASS | alto |
| eval-020 | Timeout de un agente en el triple paralelo | PASS | alto |

**Score del grupo:** 100%

---

## Tendencia histórica

| Versión | Score | Críticos | Fecha |
|---------|-------|----------|-------|
| vfull | 100% | 0 | 2026-04-16 |
| v1.0.1 | 93% | 0 | 2026-04-07 |
| v1.0.0 | 80% | 0 | 2026-04-07 |

### Análisis de tendencia

✅ **MEJORA:** 93% -> 100%.

---

## Evals que pasaron

- **eval-001** — Tarea solo UI (alto)
- **eval-002** — Tarea solo backend (alto)
- **eval-003** — Tarea con esquema (alto)
- **eval-004** — Tarea ambigua (medio)
- **eval-005** — Tarea de bugfix (alto)
- **eval-006** — Formato de director_report (alto)
- **eval-007** — Sufijos en paralelo (alto)
- **eval-008** — Rechazo estructurado de auditor (crítico)
- **eval-009** — Rechazo estructurado de qa (crítico)
- **eval-010** — Reintento con contexto enriquecido (alto)
- **eval-011** — Escalación correcta (crítico)
- **eval-012** — Rechazo de devops sin aprobación completa (crítico)
- **eval-013** — Curación parcial post-devops (medio)
- **eval-014** — Curación completa al cierre (medio)
- **eval-015** — Lectura de memoria antes de actuar (alto)
- **eval-016** — Orchestrator espera los tres veredictos (crítico)
- **eval-017** — Orchestrator avanza solo con triple aprobación (crítico)
- **eval-018** — Rechazo de auditor con qa y red_team pendientes (alto)
- **eval-019** — Task_id correcto end-to-end en los tres agentes del paralelo (alto)
- **eval-020** — Timeout de un agente en el triple paralelo (alto)
