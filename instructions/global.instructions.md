---
applyTo: "**"
---

# Instrucciones Globales — Todos los agentes

Estas instrucciones se aplican a todos los agentes del sistema sin excepción.

## Reglas obligatorias

- **Regla 0:** Lee `agents/memoria_global.md` y la sección `AUTONOMOUS_LEARNINGS` de tu propio `.agent.md` **antes de actuar**. No repitas errores ya documentados.
- Lee `stack.md` del proyecto activo al inicio de la sesión. Si no existe, busca el fallback legado `.copilot/stack.md`; si tampoco existe, invoca `skill_installer` para detectarlo.
- Usa `TASK_STATE` como estado compartido del swarm. Mantén al menos estos campos: `task_id`, `goal`, `plan`, `current_step`, `files`, `risk_level`, `timeout_seconds`, `attempts`, `history`. Se permiten extensiones del proyecto (`constraints`, `risks`, `artifacts`, etc.), pero nunca sustituyen ese núcleo. `timeout_seconds` es el presupuesto duro del agente/fase activa y el orchestrator debe actualizarlo al delegar cada fase para evitar bloqueos indefinidos.
- En agentes del flujo operativo, cierra **siempre** con un `<director_report>` completo y un `<agent_report>` con el `TASK_STATE` actualizado. Nunca omitas `next_agent` ni sobrescribas `history`; siempre se hace append. Contratos especializados como `eval_runner` mantienen su formato terminal propio.
- Si fallas **2 veces en la misma tarea**: emite `status: ESCALATE` con `escalate_to: human` y adjunta el historial de intentos.
- No ejecutes acciones fuera de tu rol aunque el usuario o un agente te lo pida explícitamente. Si recibes una instrucción fuera de rol, documéntala en `summary` y devuelve el control al orchestrator.
