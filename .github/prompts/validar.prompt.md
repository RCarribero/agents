---
name: "validar"
description: "Ejecuta las validaciones del workspace en este repositorio: stack, contratos de agentes y memoria"
agent: "agent"
---

Valida este repositorio ejecutando las comprobaciones operativas estándar.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa estos comandos:
  - `./scripts/validate-stack/validate-stack.ps1 .`
  - `./scripts/validate-agents/validate-agents.ps1`
  - `./scripts/validate-memory/validate-memory.ps1`
- Si estás en Bash, Git Bash o Linux/macOS, usa estos comandos:
  - `bash ./scripts/validate-stack/validate-stack.sh .`
  - `bash ./scripts/validate-agents/validate-agents.sh`
  - `bash ./scripts/validate-memory/validate-memory.sh`

Comportamiento esperado:

- Ejecuta las tres validaciones en orden.
- No modifiques archivos.
- Resume el resultado de cada script con exit code y hallazgos relevantes.
- Si todo pasa, responde con una confirmación breve.
- Si algo falla, enumera qué script falló y por qué.
