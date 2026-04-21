# Protocolo de Bundle de Verificación (Fase 3 → Fase 4)

Define el contrato de consenso entre `auditor`, `qa`, `red_team` y la habilitación de `devops`.

---

## verification_cycle

Formato: `<task_id_base>.r<retry_count>` o `<task_id_base>.override<N>.r<M>`.

- Identificador único por ciclo. Nunca reutilizable en la misma sesión para el mismo ámbito.
- El orchestrator lo define al iniciar Fase 3 y lo propaga explícitamente como `context.verification_cycle` a los tres verificadores.
- Los tres verificadores deben **ecoar exactamente** ese valor en su `director_report`. Reconstruirlo desde `task_id` sufijado está prohibido.
- El prefijo del `verification_cycle` debe ser **idéntico** al `task_id` base de la invocación. `devops` rechaza cualquier mismatch.

## Campos consensuados (los tres reports deben coincidir)

| Campo | Regla de consenso |
|---|---|
| `task_id` (base) | igual en los tres |
| `verification_cycle` | igual en los tres y prefijo == task_id base |
| `verified_files` | igualdad exacta como conjunto normalizado (no subconjunto) |
| `branch_name` | los tres deben emitirlo y coincidir |
| `verified_digest` | recomputado independientemente, idéntico en los tres |
| `test_status` | emitido por `qa` en ese ciclo |
| `eval_gate_status` | `APROBADO` \| `SKIPPED_BY_AUTHORIZATION` \| `N/A` |

**Exclusión obligatoria:** `session_log.md` no forma parte de `verified_files`, no entra en el digest, no entra en el payload deployable.

## Validación de bundle (orchestrator + devops)

Ambos invocan `python scripts/validate_bundle.py` con los tres director_reports y abortan ante cualquier mismatch:

- Cualquier valor divergente entre los tres reports → bundle inválido.
- Cualquier campo del bundle que no coincida con la invocación actual de `devops` → rechazo.
- `verified_digest` recomputado por `devops` sobre el staging exacto debe coincidir con el del bundle.

## Payload del commit (devops)

`devops` debe verificar que el índice git contiene exactamente `verified_files` (sin extras), reconstruir un staging limpio solo con esos archivos, recomputar el digest sobre el snapshot staged y compararlo contra `verified_digest` antes del commit. Cualquier archivo extra en el índice o cualquier blob cuyo contenido no coincida invalida la fase.

## Contexto mínimo obligatorio para devops

Al invocar devops, el orchestrator SIEMPRE incluye:

- `test_status`: resultado de tests con explicación de fallos esperados/intencionales vs reales
- `orchestrator_authorization: APROBADO` — autorización explícita desde la primera invocación
- `files_to_commit`: lista exhaustiva == `verified_files`
- `commit_message`: mensaje completo y formateado
- `known_failures`: lista de fallos preexistentes que NO bloquean el commit
- `bundle`: los tres director_reports concatenados (ver `validate_bundle.py`)
