# Eval Report — {{fecha}} — v{{version}}

## Resumen

| Métrica | Valor |
|---------|-------|
| **Total evals** | {{total}} |
| **PASS** | {{pass}} |
| **FAIL** | {{fail}} |
| **PARTIAL** | {{partial}} |
| **Score** | {{score}}% |
| **Fallos críticos** | {{critical_failures}} |

---

## Estado general

{{#if critical_failures}}
⚠️ **ATENCIÓN:** Se detectaron {{critical_failures}} fallos críticos. El sistema NO está listo para deploy.
{{else}}
✅ **OK:** No se detectaron fallos críticos. El sistema puede avanzar a QA completo.
{{/if}}

{{#if score_degradation}}
⚠️ **REGRESIÓN DETECTADA:** El score bajó {{score_degradation}}% respecto a la versión anterior ({{previous_version}}: {{previous_score}}%).
{{/if}}

---

## Fallos críticos

{{#if critical_failures}}
Los siguientes fallos tienen peso **crítico** y bloquean el despliegue:

{{#each critical_failures}}
### {{eval_id}} — {{nombre}}

**Descripción:** {{descripcion}}

**Campo/regla violada:** {{campo_violado}}

**Output real:**
```
{{output_real}}
```

**Expected:**
```
{{expected}}
```

**Impacto:** {{impacto}}

**Recomendación:** {{recomendacion}}

---

{{/each}}
{{else}}
✅ No se detectaron fallos críticos.
{{/if}}

---

## Fallos no críticos

{{#if non_critical_failures}}
Los siguientes fallos tienen peso **alto** o **medio** pero no bloquean deploy:

{{#each non_critical_failures}}
### {{eval_id}} — {{nombre}}

**Resultado:** {{resultado}} ({{criterios_cumplidos}}/{{criterios_totales}} criterios)

**Detalle:** {{detalle}}

**Impacto:** {{impacto}}

**Recomendación:** {{recomendacion}}

---

{{/each}}
{{else}}
✅ No se detectaron fallos no críticos.
{{/if}}

---

## Resultados PARTIAL

{{#if partial_results}}
Las siguientes evals terminaron en estado **PARTIAL** (cumplimiento parcial de criterios):

{{#each partial_results}}
### {{eval_id}} — {{nombre}}

**Criterios cumplidos:** {{criterios_cumplidos}}/{{criterios_totales}}

**Detalle:**
{{#each criterios}}
- {{criterio}}: {{#if cumplido}}✅{{else}}❌{{/if}} {{detalle}}
{{/each}}

**Razón del estado parcial:** {{razon}}

---

{{/each}}
{{else}}
✅ No hay resultados parciales.
{{/if}}

---

## Detalles por grupo

### Routing (5 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
{{#each routing_evals}}
| {{eval_id}} | {{nombre}} | {{resultado}} | {{peso}} |
{{/each}}

**Score del grupo:** {{routing_score}}%

---

### Contratos (4 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
{{#each contratos_evals}}
| {{eval_id}} | {{nombre}} | {{resultado}} | {{peso}} |
{{/each}}

**Score del grupo:** {{contratos_score}}%

---

### Reintentos (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
{{#each reintentos_evals}}
| {{eval_id}} | {{nombre}} | {{resultado}} | {{peso}} |
{{/each}}

**Score del grupo:** {{reintentos_score}}%

---

### Memoria (3 evals)

| Eval ID | Nombre | Resultado | Peso |
|---------|--------|-----------|------|
{{#each memoria_evals}}
| {{eval_id}} | {{nombre}} | {{resultado}} | {{peso}} |
{{/each}}

**Score del grupo:** {{memoria_score}}%

---

## Tendencia histórica

Comparación de scores de las últimas 5 versiones:

| Versión | Score | Críticos | Fecha |
|---------|-------|----------|-------|
{{#each versiones}}
| {{version}} | {{score}}% | {{criticos}} | {{fecha}} |
{{/each}}

### Análisis de tendencia

{{#if mejora}}
✅ **MEJORA:** El score subió {{mejora_porcentaje}}% respecto a la versión anterior.
{{else if regresion}}
⚠️ **REGRESIÓN:** El score bajó {{regresion_porcentaje}}% respecto a la versión anterior.
{{else}}
ℹ️ **ESTABLE:** El score se mantiene estable respecto a la versión anterior (variación < 5%).
{{/if}}

---

## Evals que pasaron

{{#if passed_evals}}
Las siguientes evals pasaron exitosamente:

{{#each passed_evals}}
- **{{eval_id}}** — {{nombre}} ({{peso}})
{{/each}}
{{else}}
⚠️ Ninguna eval pasó completamente.
{{/if}}

---

## Tiempos de ejecución

| Eval ID | Tiempo (ms) | Timeout |
|---------|-------------|---------|
{{#each execution_times}}
| {{eval_id}} | {{tiempo_ms}} | {{#if timeout}}⚠️ SÍ{{else}}No{{/if}} |
{{/each}}

**Tiempo total de ejecución:** {{tiempo_total_ms}} ms ({{tiempo_total_min}} min)

{{#if timeouts}}
⚠️ **ATENCIÓN:** {{timeouts}} evals superaron el timeout de 5 minutos y se marcaron como FAIL.
{{/if}}

---

## Recomendaciones

{{#if critical_failures}}
### Acciones críticas (requeridas antes de deploy)

{{#each critical_actions}}
1. **{{accion}}** — {{justificacion}}
{{/each}}
{{/if}}

{{#if non_critical_failures}}
### Acciones recomendadas (mejoran la calidad)

{{#each recommended_actions}}
1. **{{accion}}** — {{justificacion}}
{{/each}}
{{/if}}

{{#if partial_results}}
### Evals a completar

Las siguientes evals terminaron en estado PARTIAL. Se recomienda ejecutarlas en condiciones completas:

{{#each partial_evals}}
- **{{eval_id}}** — {{razon}}
{{/each}}
{{/if}}

---

## Metadata del informe

- **Versión del sistema:** {{version}}
- **Fecha de ejecución:** {{fecha}}
- **Modo de ejecución:** {{modo}}
- **Grupo ejecutado:** {{grupo}}
- **Eval específica:** {{eval_id}}
- **Versión del catálogo:** {{catalog_version}}
- **Generador:** eval_runner.agent.md

---

## Próximos pasos

{{#if critical_failures}}
1. **BLOQUEO DE DEPLOY:** No avanzar a producción hasta corregir los {{critical_failures}} fallos críticos.
2. Revisar cada fallo crítico en la sección correspondiente.
3. Aplicar las recomendaciones de corrección.
4. Re-ejecutar las evals afectadas en modo `single`.
5. Una vez corregidos, ejecutar modo `full` completo.
{{else if score_degradation}}
1. Investigar la causa de la regresión de {{score_degradation}}%.
2. Revisar los commits entre {{previous_version}} y {{version}}.
3. Re-ejecutar el grupo afectado tras correcciones.
{{else}}
1. ✅ Sistema en buen estado. Proceder con QA completo.
2. Considerar ejecutar evals periódicamente (semanal) para detectar regresiones tempranas.
3. Documentar nuevos patrones en `memoria_global.md` tras este ciclo.
{{/if}}

---

**Fin del informe**
