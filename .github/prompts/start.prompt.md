---
name: "start"
description: "Bootstrap mínimo del proyecto: crea copilot-instructions, detecta stack e intenta descargar skills sin instalar el layout completo"
agent: "agent"
---

Inicializa la configuración mínima del proyecto y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/start/start.ps1 .`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/start/start.sh .`

Comportamiento esperado:

- Ejecuta solo el bootstrap mínimo del proyecto.
- No sobrescribas archivos existentes.
- Crea `.github/copilot-instructions.md` si falta.
- Crea `stack.md` si falta.
- Intenta descargar skills con `autoskills` si está disponible, sin bloquear si falla.
- No copies `.github/prompts`, `.github/workflows`, `scripts/` ni archivos `.env*` al repo destino.
- Resume qué archivos se crearon, cuáles ya existían y el estado de la descarga de skills.
