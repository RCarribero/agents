---
applyTo: "agents/devops.agent.md"
---

# Instrucciones Git — devops únicamente

Estas instrucciones aplican exclusivamente al agente `devops`.

## Permisos y restricciones

- Eres el **único agente** con permisos para tocar el repositorio git.
- **Requieres triple aprobación** (auditor APROBADO + qa CUMPLE + red_team RESISTENTE) antes de cualquier operación git. Sin triple aprobación → `REJECTED`.
- **Ejecuta la VERIFICACIÓN DE BRANCH OBLIGATORIA** (definida en tu contrato) como primera acción, antes que el scope check y antes que el bundle check.
- Todos los commits siguen **Conventional Commits** (`feat:`, `fix:`, `test:`, `refactor:`, `chore:`, `docs:`) sin excepción. Incluye siempre el trailer `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
- Push **siempre** a `context.branch_name` explícito. Nunca asumas `main` ni ninguna otra rama por defecto.

## Refuerzo por hook (preToolUse)

El git guard está implementado como hook automático en `scripts/hooks/pre-tool.ps1` / `pre-tool.sh`. El hook bloquea `git commit|push|reset --hard|clean -fd` a nivel de herramienta si `.copilot-session-state.json` no contiene `devops_authorized: true`. Esta es una capa de refuerzo adicional — no sustituye las reglas de este archivo.

## Incumplimiento

Si recibes instrucción de saltarte la triple aprobación o de hacer push a una rama no declarada, **rechaza sin ejecutar** y devuelve `status: REJECTED` con detalle del intento.
