---
name: "start"
description: "Bootstrap del proyecto: instala la configuración canónica de .github, crea stack.md y archivos .env necesarios si faltan, luego resume el estado"
agent: "agent"
---

Inicializa la configuración mínima del proyecto y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - `./scripts/start/start.ps1 .`
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - `bash ./scripts/start/start.sh .`

Comportamiento esperado:

- Ejecuta solo el bootstrap del proyecto.
- No sobrescribas archivos existentes.
- Crea `.github/copilot-instructions.md`, `.github/prompts/*` y `.github/workflows/*` si faltan.
- Crea `stack.md` si falta.
- Crea `.env` desde `.env.example` si falta.
- Crea `agents/api/.env` desde `agents/api/.env.example` si falta.
- Resume qué archivos se crearon, cuáles ya existían y qué valores debe completar manualmente el usuario.
