# Protocolo de Protección de Agentes

Reglas que aplican cuando una tarea modifica un `.agent.md` o el contrato estándar del sistema. El orchestrator conserva autoridad exclusiva para aprobar y revertir estos cambios.

---

## Trigger de evaluación

**¿La tarea modifica un `.agent.md` o el contrato estándar del sistema?**

→ **ANTES de aplicar cualquier cambio:**

1. **Ejecutar baseline:** Invocar `eval_runner` con `modo: "full"` → guardar resultado como `PRE_CHANGE_SCORE`
2. **Aplicar cambio propuesto:** Modificar el archivo `.agent.md` o archivo de contrato
3. **Ejecutar post-change:** Invocar `eval_runner` con `modo: "full"` → guardar resultado como `POST_CHANGE_SCORE`
4. **Comparar scores:**

   **Si `POST_CHANGE_SCORE >= PRE_CHANGE_SCORE` Y ninguna eval crítica nueva en FAIL:**
   - → Cambio APROBADO → continuar flujo normal
   - → Emitir reporte de comparación en el `director_report`

   **Si `POST_CHANGE_SCORE < PRE_CHANGE_SCORE` O alguna eval crítica pasa a FAIL:**
   - → REVERTIR cambio inmediatamente
   - → Escalar a human con diff de scores completo
   - → Incluir en escalación: qué eval falló, score antes/después, archivo modificado

## Reglas de autoridad

- `eval_runner` es observador pasivo — solo ejecuta evals y devuelve reportes, nunca modifica archivos
- El `orchestrator` conserva autoridad exclusiva para aprobar y revertir cambios a `.agent.md`. La edición material puede delegarse al implementador designado bajo esa autoridad, pero la decisión de aplicar o revertir es siempre del orchestrator. Los subagentes **no modifican `.agent.md` por cuenta propia**.
- Esta regla aplica también al propio `orchestrator.agent.md` — meta-validación incluida

## Casos especiales

- **Hotfix urgente:** El usuario puede autorizar saltar el trigger con `APROBAR_SIN_EVAL`. La autorización es de **un solo uso** — queda ligada de forma exclusiva al `task_id`, `verification_cycle` (`<task_id_base>.r<N>` o `<task_id_base>.override<N>.r<M>`), `branch_name`, lista exacta de artifacts y `verified_digest` en el momento de la aprobación. Cualquier cambio en archivos, `branch_name`, nuevo reintento, diferente `verification_cycle` **o cualquier cambio de contenido que altere `verified_digest`** invalida la autorización previa y exige una nueva aprobación explícita del usuario. Registrar en `session_log.md` con motivo explícito, `verification_cycle`, `branch_name` y artifacts exactos. **Cuando se use APROBAR_SIN_EVAL, el bundle enviado a `devops` debe incluir obligatoriamente `eval_gate_status: SKIPPED_BY_AUTHORIZATION` y `eval_authorization_scope: { task_id, verification_cycle, branch_name, artifacts, verified_digest }` exactos. Sin estos campos completos en el bundle, Fase 4 no puede abrirse y `devops` debe rechazar.**
- **eval_runner tarda más de 2 minutos:** El cambio queda en estado **PENDIENTE SIN VALIDAR** — no se considera activo ni aprobado. Notificar al usuario. Si el usuario no instruye explícitamente cómo proceder, **revertir el cambio**. Nunca continuar el flujo como si el cambio estuviera aprobado.
- **Sin baseline previo:** No se puede aprobar automáticamente el primer estado modificado sin baseline. Opciones: (a) ejecutar `eval_runner` en modo baseline-only para registrar el estado pre-cambio antes de modificar, o (b) el usuario autoriza explícitamente con `APROBAR_SIN_EVAL`. El sistema **no aprueba ni avanza** sin una de estas dos condiciones.

## Formato del reporte de comparación

```markdown
## Eval Comparison Report

| Métrica       | Pre-cambio | Post-cambio | Delta   |
|---------------|------------|-------------|---------|
| Score general | 93%        | 95%         | +2%     |
| Routing       | 100%       | 100%        | 0%      |
| Contratos     | 75%        | 75%         | 0%      |
| Reintentos    | 100%       | 100%        | 0%      |
| Memoria       | 100%       | 100%        | 0%      |
| Críticos FAIL | 0          | 0           | 0       |

Decisión: APROBADO — score igual o mejor, sin nuevos críticos
```

## Logging en session_log.md

Por cada activación del trigger, añadir entrada:
```
[YYYY-MM-DD HH:MM] EVAL_TRIGGER | task: <id> | orchestrator → eval_runner | status: APROBADO|REJECTED|SKIPPED | artifacts: [<ruta/exacta.agent.md>] | pre: XX% → post: YY% | verification_cycle: <task_id>.r<N> | retry_count: N [| escalado: human]
```
