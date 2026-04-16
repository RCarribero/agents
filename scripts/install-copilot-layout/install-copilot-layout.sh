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
  el perfil del usuario. Después de esto, /start, /dockerize,
  /productionize, /skill-installer y /create-project estarán disponibles en cualquier
  carpeta/workspace.

Opciones:
  --force     Compatibilidad. La sobrescritura ya es el comportamiento por defecto.
  -h, --help  Muestra esta ayuda.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FORCE=1

created=()
updated=()
skipped=()
missing=()
MCP_STATUS="SKIPPED"
MCP_DETAILS="python/python3 no disponible"
mcp_synced=()
mcp_unchanged=()
mcp_warned=()

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

collect_prompt_install_dirs() {
  USER_PROMPTS_DIR="$(detect_user_prompts_dir)"
  USER_ROOT_DIR="$(dirname "$USER_PROMPTS_DIR")"
  PROMPT_INSTALL_DIRS=("$USER_PROMPTS_DIR")

  if [ -z "${VSCODE_USER_PROMPTS_FOLDER:-}" ]; then
    local profiles_dir="$USER_ROOT_DIR/profiles"
    if [ -d "$profiles_dir" ]; then
      while IFS= read -r -d '' profile_dir; do
        PROMPT_INSTALL_DIRS+=("$profile_dir/prompts")
      done < <(find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    fi
  fi
}

prompt_label() {
  local prompt_dir="$1"
  local name="$2"

  if [ "$prompt_dir" = "$USER_PROMPTS_DIR" ]; then
    echo "prompt:user:$name"
    return 0
  fi

  case "$prompt_dir" in
    "$USER_ROOT_DIR"/profiles/*/prompts)
      local profile_id
      profile_id="$(basename "$(dirname "$prompt_dir")")"
      echo "prompt:profile:$profile_id:$name"
      return 0
      ;;
  esac

  echo "prompt:$name"
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
  local label="$4"
  local existed=0

  mkdir -p "$(dirname "$target")"

  if [ -f "$target" ]; then
    existed=1
  fi

  if [ "$existed" -eq 1 ] && [ "$FORCE" -ne 1 ]; then
    skipped+=("$label")
    return 0
  fi

  printf "%s\n" "$content" > "$target"

  if [ "$existed" -eq 1 ]; then
    updated+=("$label")
  else
    created+=("$label")
  fi
}

# ─── MCP sync helpers ──────────────────────────────────────────────────────────

_sync_one_mcp_json() {
  # Merges the four MCP server entries into target mcp.json (create if absent).
  # Prints comma-separated list of added keys, or empty string if nothing changed.
  local target="$1"
  "${MCP_JSON_PYTHON:-python3}" - "$target" <<'PYEOF'
import sys, json, os

target = sys.argv[1]

SERVERS = {
  "io.github.github/github-mcp-server": {
    "type": "http",
    "url": "https://api.githubcopilot.com/mcp/",
    "gallery": "https://api.mcp.github.com",
    "version": "0.33.0",
  },
  "com.supabase/mcp": {
    "type": "http",
    "url": "https://mcp.supabase.com/mcp",
    "gallery": "https://api.mcp.github.com",
    "version": "0.7.0",
  },
  "com.stripe/mcp": {
    "type": "http",
    "url": "https://mcp.stripe.com",
    "gallery": "https://api.mcp.github.com",
    "version": "0.2.4",
  },
  "com.vercel/vercel-mcp": {
    "type": "http",
    "url": "https://mcp.vercel.com",
    "gallery": "https://api.mcp.github.com",
    "version": "0.0.3",
  },
}

data = {}
if os.path.isfile(target):
    with open(target, encoding="utf-8") as f:
        data = json.load(f)

if not isinstance(data.get("servers"), dict):
    data["servers"] = {}
if "inputs" not in data:
    data["inputs"] = []

known_urls = {
    v["url"]
    for v in data["servers"].values()
    if isinstance(v, dict) and "url" in v
}

added = []
for key, entry in SERVERS.items():
    if key in data["servers"]:
        continue
    if entry.get("url") in known_urls:
        continue
    data["servers"][key] = entry
    known_urls.add(entry["url"])
    added.append(key)

os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(",".join(added))
PYEOF
}

run_mcp_sync_layout() {
  local MCP_JSON_PYTHON=""
  for _py in python3 python; do
    if command -v "$_py" >/dev/null 2>&1; then
      MCP_JSON_PYTHON="$_py"
      break
    fi
  done
  if [ -z "$MCP_JSON_PYTHON" ]; then
    MCP_STATUS="SKIPPED"
    MCP_DETAILS="python/python3 no disponible"
    return 0
  fi

  local -a targets=()
  # Profile-level mcp.json files
  if [ -d "$USER_ROOT_DIR/profiles" ]; then
    while IFS= read -r -d '' _pdir; do
      targets+=("$_pdir/mcp.json")
    done < <(find "$USER_ROOT_DIR/profiles" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  fi
  # User-root mcp.json (always include; _sync_one_mcp_json creates it if absent)
  targets+=("$USER_ROOT_DIR/mcp.json")

  local had_ok=false
  local _result
  for _mcpfile in "${targets[@]}"; do
    if _result="$(_sync_one_mcp_json "$_mcpfile" 2>&1)"; then
      had_ok=true
      if [ -n "$_result" ]; then
        mcp_synced+=("$_mcpfile [+$_result]")
      else
        mcp_unchanged+=("$_mcpfile")
      fi
    else
      mcp_warned+=("WARN $_mcpfile: $_result")
    fi
  done

  if $had_ok; then
    MCP_STATUS="OK"
    MCP_DETAILS="sync completado (${#mcp_synced[@]} actualizado(s), ${#mcp_unchanged[@]} sin cambios)"
  elif [ ${#mcp_warned[@]} -gt 0 ]; then
    MCP_STATUS="WARN"
    MCP_DETAILS="${mcp_warned[0]:-error en sync}"
  fi
}

collect_prompt_install_dirs
COPILOT_TOOLS_DIR="${COPILOT_GLOBAL_TOOLS_DIR:-$USER_ROOT_DIR/copilot-tools}"
TOOLS_SCRIPTS_DIR="$COPILOT_TOOLS_DIR/scripts"
TOOLS_TEMPLATES_DIR="$COPILOT_TOOLS_DIR/repo-templates"

BASH_SCRIPTS_DIR="$TOOLS_SCRIPTS_DIR"
if command -v cygpath >/dev/null 2>&1; then
  BASH_SCRIPTS_DIR="$(cygpath -u "$TOOLS_SCRIPTS_DIR")"
fi

for prompt_dir in "${PROMPT_INSTALL_DIRS[@]}"; do
  mkdir -p "$prompt_dir"
done
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

for prompt_dir in "${PROMPT_INSTALL_DIRS[@]}"; do
write_prompt "start" "$prompt_dir/start.prompt.md" "---
name: \"start\"
description: \"Bootstrap global mínimo del proyecto: crea copilot-instructions, detecta stack e intenta descargar skills\"
agent: \"agent\"
---

Inicializa el repositorio actual usando el toolkit global y resume el resultado.

Reglas de ejecución:

- Si estás en Windows/PowerShell, usa este comando:
  - & \"$TOOLS_SCRIPTS_DIR/start/start.ps1\" .
- Si estás en Bash, Git Bash o Linux/macOS, usa este comando:
  - bash \"$BASH_SCRIPTS_DIR/start/start.sh\" .

Comportamiento esperado:

- Ejecuta solo el bootstrap mínimo del proyecto actual.
- Sobrescribe archivos existentes.
- Crea .github/copilot-instructions.md si falta.
- Crea stack.md si falta.
- Intenta descargar skills con autoskills si está disponible, sin bloquear si falla.
- No copies .github/prompts, .github/workflows, scripts ni archivos .env* al repo destino.
- Resume qué archivos se crearon o actualizaron y el estado de la descarga de skills.
" "$(prompt_label "$prompt_dir" "start")"
done

# Prompts complejos: se copian directo desde el source (no generados inline)
if [ -d "$SOURCE_ROOT/.github/prompts" ]; then
  while IFS= read -r -d '' _prompt_path; do
    _prompt_file="$(basename "$_prompt_path")"
    _prompt_name="${_prompt_file%.prompt.md}"
    if [ "$_prompt_name" = "start" ]; then
      continue
    fi

    for prompt_dir in "${PROMPT_INSTALL_DIRS[@]}"; do
      copy_file "$_prompt_path" "$prompt_dir/$_prompt_file" "$(prompt_label "$prompt_dir" "$_prompt_name")"
    done
  done < <(find "$SOURCE_ROOT/.github/prompts" -maxdepth 1 -type f -name '*.prompt.md' -print0 | sort -z)
else
  missing+=("global-prompts:*.prompt.md")
fi

run_mcp_sync_layout || true

echo "=== install-copilot-layout.sh ==="
echo "Origen:           $SOURCE_ROOT"
echo "Prompts base:     $USER_PROMPTS_DIR"
if [ ${#PROMPT_INSTALL_DIRS[@]} -gt 1 ]; then
  echo "Prompts de perfil:"
  for prompt_dir in "${PROMPT_INSTALL_DIRS[@]}"; do
    if [ "$prompt_dir" != "$USER_PROMPTS_DIR" ]; then
      echo "  - $prompt_dir"
    fi
  done
fi
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
echo "MCP sync:"
echo "  - estado: $MCP_STATUS"
echo "  - detalle: $MCP_DETAILS"
if [ ${#mcp_synced[@]} -gt 0 ]; then
  for _r in "${mcp_synced[@]}"; do
    echo "    updated: $_r"
  done
fi
if [ ${#mcp_warned[@]} -gt 0 ]; then
  for _w in "${mcp_warned[@]}"; do
    echo "    $_w"
  done
fi

echo ""
echo "Siguiente paso: recarga VS Code para ver /start, /dockerize, /productionize, /skill-installer y /create-project como prompts globales."