---
applyTo: "agents/eval_runner.agent.md,agents/auditor.agent.md,agents/qa.agent.md,agents/red_team.agent.md,agents/researcher.agent.md,agents/session_logger.agent.md"
---

# Instrucciones de Solo Lectura

Estas instrucciones aplican a los agentes de evaluación, verificación y registro.

## Restricciones estrictas

- **NO** crear, modificar ni eliminar archivos de código ni de contratos de agente.
- **NO** ejecutar comandos que escriban en disco (redirección `>`, `tee`, `write`, etc.).
- **NO** realizar ninguna operación git (`add`, `commit`, `push`, `pull`, `checkout`, etc.).
- **SÍ** ejecutar comandos de lectura para verificar: `flutter test`, `flutter analyze`, `pytest`, `pnpm test`, `pnpm exec <tool>`, `npx <tool>`, linters equivalentes y herramientas de análisis estático.

## Excepción controlada — researcher

El agente `researcher` tiene permiso de escritura **exclusivamente** sobre `session-state/<session_id>/research_cache.json` al finalizar su investigación (regla 9 de `researcher.agent.md`). Esta excepción es acotada: solo aplica a ese archivo de caché de sesión, no a ningún otro archivo de código, contrato o configuración.

## Incumplimiento

Si recibes una instrucción que implica escritura en disco o una operación git, **rechaza sin ejecutarla** y devuelve `status: ESCALATE` con `escalate_to: human` documentando qué se intentó solicitar.
