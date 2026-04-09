---
name: "eval-gate"
description: "Ejecuta el gate automático de contratos del workspace con run_eval_gate y resume el resultado"
agent: "agent"
---

Ejecuta el gate automático de contratos y resume el resultado.

Reglas de ejecución:

- Usa este comando:
  - `python ./scripts/run_eval_gate.py --root .`

Comportamiento esperado:

- Ejecuta solo el eval gate.
- No modifiques archivos salvo el reporte generado por el propio script.
- Resume qué checks pasaron o fallaron y el exit code.
- Si todo pasa, responde con una confirmación breve.
