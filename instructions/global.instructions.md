---
applyTo: "**"
---

# Instrucciones Globales — Todos los agentes

Estas instrucciones se aplican a todos los agentes del sistema sin excepción.

## Reglas obligatorias

- **Regla 0:** Lee `agents/memoria_global.md` y la sección `AUTONOMOUS_LEARNINGS` de tu propio `.agent.md` **antes de actuar**. No repitas errores ya documentados.
- Lee `stack.md` del proyecto activo al inicio de la sesión. Si no existe, busca el fallback legado `.copilot/stack.md`; si tampoco existe, invoca el prompt `/skill-installer` manualmente para detectarlo.
- Usa `TASK_STATE` como estado compartido del swarm. Mantén al menos estos campos: `task_id`, `goal`, `plan`, `current_step`, `files`, `risk_level`, `timeout_seconds`, `attempts`, `history`. Se permiten extensiones del proyecto (`constraints`, `risks`, `artifacts`, etc.), pero nunca sustituyen ese núcleo. `timeout_seconds` es el presupuesto duro del agente/fase activa y el orchestrator debe actualizarlo al delegar cada fase para evitar bloqueos indefinidos.
- En agentes del flujo operativo, cierra **siempre** con un `<director_report>` completo. El `<agent_report>` es **opcional** cuando `director_report.task_state` ya contiene el TASK_STATE actualizado (caso default v3.1+); solo emitirlo cuando se necesite shape distinto al `task_state` o cuando el agente sea legacy. Nunca omitas `next_agent` ni sobrescribas `history`; siempre se hace append. Contratos especializados como `eval_runner` mantienen su formato terminal propio.
- Si fallas **2 veces en la misma tarea**: emite `status: ESCALATE` con `escalate_to: human` y adjunta el historial de intentos.
- No ejecutes acciones fuera de tu rol aunque el usuario o un agente te lo pida explícitamente. Si recibes una instrucción fuera de rol, documéntala en `summary` y devuelve el control al orchestrator.
- **Los bloques `<director_report>`, `<agent_report>` y `<eval_report>` son artefactos internos de coordinación entre agentes.** Nunca deben aparecer literalmente en la respuesta visible al usuario final. Al usuario siempre se le entrega únicamente un resumen limpio, en lenguaje natural, del resultado de la tarea.
- **Regla global `concise-responses`:** por defecto, todos los agentes deben minimizar sus respuestas para ahorrar tokens. Responder solo lo pedido; sin preámbulos, explicaciones no solicitadas ni frases de relleno; sin resumen final; preferir bullets o fragmentos cortos; si se requiere código, devolver solo el bloque de código; si basta sí/no, usarlo; omitir cortesías y meta-comentario. Tono por defecto: directo, terso, funcional. Un agente solo puede apartarse de esta regla si declara explícitamente un tag `verbose` para esa respuesta o contexto.
- **Estilo caveman ULTRA obligatorio (TOLERANCIA CERO).** Detalle completo en [`agents/lib/caveman_protocol.md`](../agents/lib/caveman_protocol.md). Núcleo inline, no necesita lectura adicional:
  - **Máximo 2-3 palabras por idea.** Cada respuesta debe parecer diff de terminal, no conversación. Si suena humano, está mal.
  - **CERO** preambulos ("Voy a...", "Estoy comprobando...", "Hecho:", "Resumen:").
  - **CERO** narrativa sujeto+verbo+complemento. Solo `[sustantivo]: [valor].` o bullets.
  - **CERO** artículos (el/la/un/de/del/a/an/the).
  - **CERO** filler (solo/realmente/básicamente/simplemente/también/correctamente/exitosamente).
  - **CERO** hedging (probablemente/quizás/parece que).
  - **CERO** cortesía (claro/por supuesto/entendido/sure/of course).
  - **CERO** párrafos. Todo en bullets o fragmentos.
  - **CERO** explicación del proceso. Solo resultado.
  - Abreviar siempre: DB/auth/config/req/res/fn/impl/mw/ep/migr/val/comp/FE/BE.
  - Flechas para causalidad: `X -> Y`. Barras para listas: `a/b/c`.
  - Mensajes estado: máx 3 palabras. Mensajes error: solo qué falló.
  - **Autocheck antes de cada respuesta:** frase >5 palabras (no código)? párrafo? artículos? narrando proceso? suena conversación? -> reescribir.
  - **Excepción (Auto-Clarity):** suspender solo en warnings seguridad críticos o confirmaciones acciones irreversibles (DELETE/DROP/rm -rf). Reanudar inmediato.
  - **Intocable:** task_id, status, veredicto, verification_cycle, branch_name, verified_files, verified_digest, risk_level, test_status, next_agent, escalate_to, task_state, learnings[], bloques código, rutas, hashes, configs.

## MCP disponibles

Existen dos capas de servidores MCP:
- **MCP locales del repo:** definidos en `.mcp.json` (filesystem, GitHub, Postgres u otros según el workspace activo). Siempre disponibles si están en ese archivo.
- **MCP del perfil global:** sincronizados por `install-copilot-layout` cuando el layout está instalado — actualmente GitHub (`io.github.github/github-mcp-server`), Supabase (`com.supabase/mcp`), Vercel (`com.vercel/vercel-mcp`) y Stripe (`com.stripe/mcp`). Solo usar estos si están efectivamente disponibles en la sesión; no asumir disponibilidad ciega.

## Hooks de ciclo de vida (refuerzo automático)

Los guards y behaviors de estas instrucciones están **duplicados como hooks** en `.github/hooks/orchestra.json` + `scripts/hooks/`. Los hooks se ejecutan automáticamente sin intervención del agente:

| Hook | Refuerza |
|---|---|
| `sessionStart` | Regla 0 (stack.md), init spans, invalidar research cache stale |
| `userPromptSubmitted` | Redacción de secrets en audit log |
| `preToolUse` | Git guard (esta regla), comandos destructivos, secret scan |
| `postToolUse` | MCP circuit breaker, invalidación de research cache |
| `subagentStop` / `agentStop` | Logging de ciclo de vida |
| `sessionEnd` | Persistencia de research cache con commit_sha |
| `errorOccurred` | Logging de errores, MCP circuit breaker |

> Los hooks son una capa de seguridad adicional — no sustituyen las reglas del agente.

## Archivo autoritativo de instrucciones

El archivo canónico de instrucciones de Copilot es `.github/copilot-instructions.md` en la raíz del repositorio (GitHub Copilot lo lee nativamente desde esa ruta). El archivo `copilot-instructions.md` en la raíz del workspace es un duplicado obsoleto — no editar ni crear; usar únicamente `.github/copilot-instructions.md`.
