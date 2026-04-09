---
name: "metrics"
description: "Consulta las métricas del workspace con agent-metrics y resume el resultado"
agent: "agent"
---

Consulta las métricas del sistema y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/agent-metrics/agent-metrics.ps1 --agents`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/agent-metrics/agent-metrics.sh --agents`

Comportamiento esperado:

- Ejecuta solo la consulta de métricas.
- No modifiques archivos.
- Resume los datos relevantes disponibles o el error de conexión si falla.
- Si todo pasa, responde con una confirmación breve.
