---
name: "lint"
description: "Ejecuta el lint del workspace en este repositorio con run-lint y resume el resultado"
agent: "agent"
---

Ejecuta el linter del repositorio y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/run-lint/run-lint.ps1 . --json`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/run-lint/run-lint.sh . --json`

Comportamiento esperado:

- Ejecuta solo el runner de lint.
- No modifiques archivos.
- Resume exit code, stack detectado y problemas relevantes si existen.
- Si pasa, responde con una confirmación breve.
