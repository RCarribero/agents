---
name: "sandbox-lint"
description: "Ejecuta el lint del workspace en sandbox y resume el resultado"
agent: "agent"
---

Ejecuta el linter del repositorio en sandbox y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/sandbox-run/sandbox-run.ps1 . lint --json`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/sandbox-run/sandbox-run.sh . lint --json`

Comportamiento esperado:

- Ejecuta solo lint en sandbox.
- No modifiques archivos.
- Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.
- Resume exit code y problemas relevantes si existen.
- Si pasa, responde con una confirmación breve.
