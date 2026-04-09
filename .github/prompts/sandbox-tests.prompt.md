---
name: "sandbox-tests"
description: "Ejecuta los tests del workspace en sandbox y resume el resultado"
agent: "agent"
---

Ejecuta los tests del repositorio en sandbox y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/sandbox-run/sandbox-run.ps1 . tests --json`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/sandbox-run/sandbox-run.sh . tests --json`

Comportamiento esperado:

- Ejecuta solo tests en sandbox.
- No modifiques archivos.
- Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.
- Resume exit code y fallos relevantes si existen.
- Si pasa, responde con una confirmación breve.
