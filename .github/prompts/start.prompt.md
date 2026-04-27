---
name: "start"
description: "Bootstrap mínimo del proyecto (copilot-instructions, stack.md, plantillas opcionales). Los hooks globales se instalan vía install-copilot-layout, no vía /start."
agent: "agent"
---

Inicializa la configuración mínima del proyecto y resume el resultado.

Nota: los hooks de orquestación globales viven en `~/.copilot/hooks/orchestra.json` y NO requieren `/start`. `install-copilot-layout` es el responsable de instalarlos. `/start` solo materializa archivos a nivel proyecto (incluidas plantillas workspace opcionales en `.github/hooks/`).

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/start/start.ps1 .`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/start/start.sh .`

Comportamiento esperado:

- Ejecuta solo el bootstrap mínimo del proyecto.
- No sobrescribe archivos existentes; solo crea los que falten.
- Crea `.github/copilot-instructions.md` si falta.
- Crea `.github/hooks/*.json` (plantillas workspace, opcionales) si faltan.
- Crea `scripts/hooks/*` (pre-tool, post-tool, etc.) si faltan.
- Crea `stack.md` si falta.
- Intenta descargar skills con `autoskills` si está disponible, sin bloquear si falla.
- No instala hooks globales: estos vienen de `install-copilot-layout` y viven en `~/.copilot/hooks/orchestra.json`.
- No copia `.github/prompts`, `.github/workflows`, otros `scripts/` fuera de `scripts/hooks` ni archivos `.env*` al repo destino.
- Resume qué archivos se crearon, cuáles ya existían y el estado de la descarga de skills.
