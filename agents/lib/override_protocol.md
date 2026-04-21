# Protocolo de Override Humano y Reset de Ciclo

Define la apertura de un ciclo supervisado tras escalación o autorización explícita del usuario.

---

## Trigger

El usuario emite instrucción explícita tras un `status: ESCALATE` o autoriza un `APROBAR_SIN_EVAL`.

## Reset y nuevo verification_cycle

| Acción | Regla |
|---|---|
| `retry_count` | reset a `0` para el nuevo ciclo |
| `verification_cycle` | nuevo formato `<task_id_base>.override<N>.r0` con `N` monotónico por sesión/ámbito |
| `task_id` base | puede mantenerse o cambiar si la tarea cambia materialmente |
| `EVAL_TRIGGER` previo | NO se hereda — debe registrarse uno fresco para el nuevo ciclo si toca `.agent.md` o usa `APROBAR_SIN_EVAL` |
| Regla de escalación `retry_count >= 2` | aplica íntegramente desde el nuevo `0`, no acumula con ciclos anteriores |

## Logging obligatorio

Antes de continuar, el orchestrator invoca `session_logger` con:

```
event_type: AGENT_TRANSITION
notes: retry_count_reset: <N>→0, override_cycle: <task_id_base>.override<N>.r0, motivo_humano: "<texto>"
```

## APROBAR_SIN_EVAL — alcance

La autorización es de **un solo uso** y queda ligada a la tupla exacta:

```
{ task_id, verification_cycle, branch_name, artifacts, verified_digest }
```

Cualquier cambio en alguno de esos campos invalida la autorización y exige nueva aprobación explícita.

El bundle a `devops` debe incluir:

- `eval_gate_status: SKIPPED_BY_AUTHORIZATION`
- `eval_authorization_scope: { task_id, verification_cycle, branch_name, artifacts, verified_digest }`

Sin esos dos campos completos, Fase 4 no puede abrirse y `devops` debe rechazar.

## Tabla de transiciones

| Estado anterior | Acción humana | Nuevo verification_cycle | retry_count | EVAL_TRIGGER |
|---|---|---|---|---|
| ESCALATE tras retry_count=2 | "continúa con X" | `<task>.override1.r0` | 0 | fresco si aplica |
| ESCALATE tras override anterior | "continúa con Y" | `<task>.override2.r0` | 0 | fresco si aplica |
| Hotfix urgente | "APROBAR_SIN_EVAL" | mismo o nuevo según contexto | mismo | SKIPPED + scope |
| Retry exitoso post-rechazo | (ninguna) | `<task>.r<N+1>` | N+1 | si aplica |
