---
name: "tests"
description: "Ejecuta los tests del workspace en este repositorio con run-tests y resume el resultado"
agent: "agent"
---

Ejecuta los tests del repositorio y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/run-tests/run-tests.ps1 . --json`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/run-tests/run-tests.sh . --json`

Comportamiento esperado:

- Ejecuta solo el runner de tests.
- No modifiques archivos.
- Resume exit code, stack detectado y fallos relevantes si existen.
- Si pasa, responde con una confirmación breve.
