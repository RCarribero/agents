---
name: "start"
description: "Bootstrap mínimo del proyecto (copilot-instructions, stack.md). Los hooks son SOLO globales vía install-copilot-layout; /start NO crea hooks workspace."
agent: "agent"
---

Inicializa la configuración mínima del proyecto y resume el resultado.

**Nota importante sobre hooks:** Los hooks de orquestación son **SOLO GLOBALES** (`~/.copilot/hooks/orchestra.json`) e instalados por `install-copilot-layout`. `/start` **NO crea ni copia hooks workspace** (`.github/hooks/`, `scripts/hooks/`).

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/start/start.ps1 .`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/start/start.sh .`

Comportamiento esperado:

- Ejecuta solo el bootstrap mínimo del proyecto.
- No sobrescribe archivos existentes; solo crea los que falten.
- Crea `.github/copilot-instructions.md` si falta.
- Crea `stack.md` si falta.
- Intenta descargar skills con `autoskills` si está disponible, sin bloquear si falla.
- **NO crea** `.github/hooks/`, `scripts/hooks/`, `.github/prompts`, `.github/workflows`, ni archivos `.env*` en el repo destino.
- Resume qué archivos se crearon, cuáles ya existían y el estado de la descarga de skills.
