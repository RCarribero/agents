#!/usr/bin/env bash
# install-copilot-layout.sh — instala prompts globales y el toolkit compartido
# para que los comandos de Copilot funcionen desde cualquier workspace.

set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  bash ./scripts/install-copilot-layout/install-copilot-layout.sh [--force]

Descripción:
  Instala prompts globales en el perfil de VS Code y un toolkit de soporte en
  el perfil del usuario. Después de esto, /start, /validar, /tests, /lint y
  el resto de prompts estarán disponibles en cualquier carpeta/workspace.

Opciones:
  --force     Sobrescribe archivos existentes en el destino.
  -h, --help  Muestra esta ayuda.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FORCE=0

created=()
updated=()
skipped=()
missing=()

while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: argumento no reconocido '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

detect_user_prompts_dir() {
  if [ -n "${VSCODE_USER_PROMPTS_FOLDER:-}" ]; then
    echo "$VSCODE_USER_PROMPTS_FOLDER"
    return 0
  fi

  local -a candidates=()
  local system_name
  system_name="$(uname -s 2>/dev/null || echo unknown)"

  case "$system_name" in
    Darwin)
      candidates+=("$HOME/Library/Application Support/Code - Insiders/User/prompts")
      candidates+=("$HOME/Library/Application Support/Code/User/prompts")
      ;;
    Linux)
      candidates+=("$HOME/.config/Code - Insiders/User/prompts")
      candidates+=("$HOME/.config/Code/User/prompts")
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if [ -n "${APPDATA:-}" ]; then
        candidates+=("$APPDATA/Code - Insiders/User/prompts")
        candidates+=("$APPDATA/Code/User/prompts")
      fi
      ;;
    *)
      ;;
  esac

  if [ ${#candidates[@]} -eq 0 ]; then
    echo "ERROR: no se pudo detectar la carpeta global de prompts. Define VSCODE_USER_PROMPTS_FOLDER." >&2
    exit 1
  fi

  for candidate in "${candidates[@]}"; do
    if [ -d "$candidate" ] || [ -d "$(dirname "$candidate")" ]; then
      echo "$candidate"
      return 0
    fi
  done

  echo "${candidates[0]}"
}

copy_file() {
  local source="$1"
  local target="$2"
  local label="$3"
  local existed=0

  mkdir -p "$(dirname "$target")"

  if [ -f "$target" ]; then
    existed=1
  fi

  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    skipped+=("$label")
    return 0
  fi

  cp "$source" "$target"

  if [ "$existed" -eq 1 ]; then
    updated+=("$label")
  else
    created+=("$label")
  fi
}

write_prompt() {
  local name="$1"
  local target="$2"
  local content="$3"
  local existed=0

  mkdir -p "$(dirname "$target")"

  if [ -f "$target" ]; then
    existed=1
  fi

  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    skipped+=("prompt:$name")
    return 0
  fi

  printf "%s\n" "$content" > "$target"

  if [ "$existed" -eq 1 ]; then
    updated+=("prompt:$name")
  else
    created+=("prompt:$name")
  fi
}

USER_PROMPTS_DIR="$(detect_user_prompts_dir)"
USER_ROOT_DIR="$(dirname "$USER_PROMPTS_DIR")"
COPILOT_TOOLS_DIR="${COPILOT_GLOBAL_TOOLS_DIR:-$USER_ROOT_DIR/copilot-tools}"
TOOLS_SCRIPTS_DIR="$COPILOT_TOOLS_DIR/scripts"
TOOLS_TEMPLATES_DIR="$COPILOT_TOOLS_DIR/repo-templates"

BASH_SCRIPTS_DIR="$TOOLS_SCRIPTS_DIR"
if command -v cygpath >/dev/null 2>&1; then
  BASH_SCRIPTS_DIR="$(cygpath -u "$TOOLS_SCRIPTS_DIR")"
fi

mkdir -p "$USER_PROMPTS_DIR"
mkdir -p "$TOOLS_SCRIPTS_DIR"
mkdir -p "$TOOLS_TEMPLATES_DIR/.github/prompts"
mkdir -p "$TOOLS_TEMPLATES_DIR/.github/workflows"

if [ -f "$SOURCE_ROOT/.github/copilot-instructions.md" ]; then
  copy_file "$SOURCE_ROOT/.github/copilot-instructions.md" "$TOOLS_TEMPLATES_DIR/.github/copilot-instructions.md" "toolkit:.github/copilot-instructions.md"
else
  missing+=("toolkit:.github/copilot-instructions.md")
fi

if [ -d "$SOURCE_ROOT/.github/prompts" ]; then
  while IFS= read -r -d '' prompt_file; do
    file_name="$(basename "$prompt_file")"
    copy_file "$prompt_file" "$TOOLS_TEMPLATES_DIR/.github/prompts/$file_name" "toolkit:.github/prompts/$file_name"
  done < <(find "$SOURCE_ROOT/.github/prompts" -maxdepth 1 -type f -name '*.prompt.md' -print0 | sort -z)
else
  missing+=("toolkit:.github/prompts/*")
fi

if [ -d "$SOURCE_ROOT/.github/workflows" ]; then
  while IFS= read -r -d '' workflow_file; do
    file_name="$(basename "$workflow_file")"
    copy_file "$workflow_file" "$TOOLS_TEMPLATES_DIR/.github/workflows/$file_name" "toolkit:.github/workflows/$file_name"
  done < <(find "$SOURCE_ROOT/.github/workflows" -maxdepth 1 -type f -name '*.yml' -print0 | sort -z)
else
  missing+=("toolkit:.github/workflows/*")
fi

if [ -f "$SOURCE_ROOT/.env.example" ]; then
  copy_file "$SOURCE_ROOT/.env.example" "$TOOLS_TEMPLATES_DIR/.env.example" "toolkit:.env.example"
else
  missing+=("toolkit:.env.example")
fi

for relative_path in \
  scripts/invoke-git-bash.ps1 \
  scripts/install-copilot-layout/install-copilot-layout.sh \
  scripts/install-copilot-layout/install-copilot-layout.ps1 \
  scripts/install-repo-layout/install-repo-layout.sh \
  scripts/install-repo-layout/install-repo-layout.ps1 \
  scripts/start/start.sh \
  scripts/start/start.ps1 \
  scripts/validate-stack/validate-stack.sh \
  scripts/validate-stack/validate-stack.ps1 \
  scripts/validate-agents/validate-agents.sh \
  scripts/validate-agents/validate-agents.ps1 \
  scripts/validate-memory/validate-memory.sh \
  scripts/validate-memory/validate-memory.ps1 \
  scripts/run-tests/run-tests.sh \
  scripts/run-tests/run-tests.ps1 \
  scripts/run-lint/run-lint.sh \
  scripts/run-lint/run-lint.ps1 \
  scripts/sandbox-run/sandbox-run.sh \
  scripts/sandbox-run/sandbox-run.ps1 \
  scripts/Dockerfile.sandbox \
  scripts/agent-metrics/agent-metrics.sh \
  scripts/agent-metrics/agent-metrics.ps1 \
  scripts/rag_indexer.py \
  scripts/run_eval_gate.py \
  scripts/token-report/token-report.sh \
  scripts/token-report/token-report.ps1 \
  scripts/verified_digest.py
do
  source_path="$SOURCE_ROOT/$relative_path"
  target_path="$COPILOT_TOOLS_DIR/$relative_path"

  if [ -f "$source_path" ]; then
    copy_file "$source_path" "$target_path" "toolkit:$relative_path"
  else
    missing+=("toolkit:$relative_path")
  fi
done

write_prompt "start" "$USER_PROMPTS_DIR/start.prompt.md" "---
name: \"start\"
description: \"Bootstrap global del proyecto: instala el layout canónico en el repo actual, crea stack.md y los .env necesarios\"
agent: \"agent\"
---

Inicializa el repositorio actual usando el toolkit global y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/start/start.ps1\" .
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/start/start.sh\" .

Comportamiento esperado:

- Ejecuta solo el bootstrap del proyecto actual.
- No sobrescribas archivos existentes.
- Resume qué archivos se crearon, cuáles ya existían y qué valores debe completar manualmente el usuario.
"

write_prompt "validar" "$USER_PROMPTS_DIR/validar.prompt.md" "---
name: \"validar\"
description: \"Ejecuta las validaciones del workspace actual con el toolkit global\"
agent: \"agent\"
---

Valida el repositorio actual ejecutando las comprobaciones operativas estándar.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa estos comandos:
  - & \"$TOOLS_SCRIPTS_DIR/validate-stack/validate-stack.ps1\" .
  - & \"$TOOLS_SCRIPTS_DIR/validate-agents/validate-agents.ps1\"
  - & \"$TOOLS_SCRIPTS_DIR/validate-memory/validate-memory.ps1\"
- Si estás en Bash, Git Bash o Linux/macOS, usa estos comandos:
  - bash \"$BASH_SCRIPTS_DIR/validate-stack/validate-stack.sh\" .
  - bash \"$BASH_SCRIPTS_DIR/validate-agents/validate-agents.sh\"
  - bash \"$BASH_SCRIPTS_DIR/validate-memory/validate-memory.sh\"

Comportamiento esperado:

- Ejecuta las tres validaciones en orden.
- No modifiques archivos.
- Resume el resultado de cada script con exit code y hallazgos relevantes.
"

write_prompt "tests" "$USER_PROMPTS_DIR/tests.prompt.md" "---
name: \"tests\"
description: \"Ejecuta los tests del workspace actual con el toolkit global\"
agent: \"agent\"
---

Ejecuta los tests del repositorio actual y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/run-tests/run-tests.ps1\" . --json
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/run-tests/run-tests.sh\" . --json

Comportamiento esperado:

- Ejecuta solo el runner de tests.
- No modifiques archivos.
- Resume exit code, stack detectado y fallos relevantes si existen.
"

write_prompt "lint" "$USER_PROMPTS_DIR/lint.prompt.md" "---
name: \"lint\"
description: \"Ejecuta el lint del workspace actual con el toolkit global\"
agent: \"agent\"
---

Ejecuta el linter del repositorio actual y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/run-lint/run-lint.ps1\" . --json
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/run-lint/run-lint.sh\" . --json

Comportamiento esperado:

- Ejecuta solo el runner de lint.
- No modifiques archivos.
- Resume exit code, stack detectado y problemas relevantes si existen.
"

write_prompt "sandbox-tests" "$USER_PROMPTS_DIR/sandbox-tests.prompt.md" "---
name: \"sandbox-tests\"
description: \"Ejecuta los tests del workspace actual en sandbox con el toolkit global\"
agent: \"agent\"
---

Ejecuta los tests del repositorio actual en sandbox y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/sandbox-run/sandbox-run.ps1\" . tests --json
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/sandbox-run/sandbox-run.sh\" . tests --json

Comportamiento esperado:

- Ejecuta solo tests en sandbox.
- No modifiques archivos.
- Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.
- Resume exit code y fallos relevantes si existen.
"

write_prompt "sandbox-lint" "$USER_PROMPTS_DIR/sandbox-lint.prompt.md" "---
name: \"sandbox-lint\"
description: \"Ejecuta el lint del workspace actual en sandbox con el toolkit global\"
agent: \"agent\"
---

Ejecuta el linter del repositorio actual en sandbox y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/sandbox-run/sandbox-run.ps1\" . lint --json
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/sandbox-run/sandbox-run.sh\" . lint --json

Comportamiento esperado:

- Ejecuta solo lint en sandbox.
- No modifiques archivos.
- Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.
- Resume exit code y problemas relevantes si existen.
"

write_prompt "rag-index" "$USER_PROMPTS_DIR/rag-index.prompt.md" "---
name: \"rag-index\"
description: \"Indexa memoria y contratos del workspace actual con el toolkit global\"
agent: \"agent\"
---

Ejecuta el indexado RAG del repositorio actual y resume el resultado.

Reglas de ejecución:

- Usa este comando:
  - python \"$BASH_SCRIPTS_DIR/rag_indexer.py\" --all

Comportamiento esperado:

- Ejecuta solo el indexador RAG.
- No modifiques archivos del workspace.
- Aclara si hubo chunks indexados, skips o errores.
"

write_prompt "metrics" "$USER_PROMPTS_DIR/metrics.prompt.md" "---
name: \"metrics\"
description: \"Consulta las métricas del workspace actual con el toolkit global\"
agent: \"agent\"
---

Consulta las métricas del sistema y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/agent-metrics/agent-metrics.ps1\" --agents
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/agent-metrics/agent-metrics.sh\" --agents

Comportamiento esperado:

- Ejecuta solo la consulta de métricas.
- No modifiques archivos.
- Resume los datos relevantes disponibles o el error de conexión si falla.
"

write_prompt "eval-gate" "$USER_PROMPTS_DIR/eval-gate.prompt.md" "---
name: \"eval-gate\"
description: \"Ejecuta el gate automático de contratos del workspace actual con el toolkit global\"
agent: \"agent\"
---

Ejecuta el gate automático de contratos y resume el resultado.

Reglas de ejecución:

- Usa este comando:
  - python \"$BASH_SCRIPTS_DIR/run_eval_gate.py\" --root .

Comportamiento esperado:

- Ejecuta solo el eval gate.
- No modifiques archivos salvo el reporte generado por el propio script.
- Resume qué checks pasaron o fallaron y el exit code.
"

echo "=== install-copilot-layout.sh ==="
echo "Origen:           $SOURCE_ROOT"
echo "Prompts globales: $USER_PROMPTS_DIR"
echo "Toolkit global:   $COPILOT_TOOLS_DIR"
echo ""

echo "Archivos creados:"
if [ ${#created[@]} -eq 0 ]; then
  echo "  - ninguno"
else
  for item in "${created[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Archivos actualizados:"
if [ ${#updated[@]} -eq 0 ]; then
  echo "  - ninguno"
else
  for item in "${updated[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Archivos omitidos:"
if [ ${#skipped[@]} -eq 0 ]; then
  echo "  - ninguno"
else
  for item in "${skipped[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Plantillas ausentes:"
if [ ${#missing[@]} -eq 0 ]; then
  echo "  - ninguna"
else
  for item in "${missing[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Siguiente paso: recarga VS Code para ver /start, /validar, /tests, /lint y el resto de prompts globales."