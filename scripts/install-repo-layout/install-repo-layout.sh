#!/usr/bin/env bash
# install-repo-layout.sh — Instala la configuración canónica de Copilot/GitHub
# dentro de un repositorio destino usando plantillas locales o del toolkit global.

set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  bash ./scripts/install-repo-layout/install-repo-layout.sh [target_root] [--force]

Descripción:
  Crea la estructura canónica de customización en .github/ y copia los archivos
  necesarios para prompts, workflows y scripts de soporte dentro del repo destino.

Opciones:
  --force     Sobrescribe archivos existentes en el destino.
  -h, --help  Muestra esta ayuda.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_ROOT=""
FORCE=0

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
      if [ -z "$TARGET_ROOT" ]; then
        TARGET_ROOT="$1"
      else
        echo "ERROR: argumento no reconocido '$1'" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
  shift
done

TARGET_ROOT="${TARGET_ROOT:-$(pwd)}"
TARGET_ROOT="$(cd "$TARGET_ROOT" && pwd)"

created=()
updated=()
skipped=()
missing=()

resolve_source_file() {
  local canonical="$1"
  local legacy="$2"

  for candidate in \
    "$SOURCE_ROOT/repo-templates/.github/$canonical" \
    "$SOURCE_ROOT/.github/$canonical" \
    "$SOURCE_ROOT/$legacy"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_source_dir() {
  local canonical="$1"
  local legacy="$2"

  for candidate in \
    "$SOURCE_ROOT/repo-templates/.github/$canonical" \
    "$SOURCE_ROOT/.github/$canonical" \
    "$SOURCE_ROOT/$legacy"
  do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_root_template() {
  local relative_path="$1"

  for candidate in \
    "$SOURCE_ROOT/repo-templates/$relative_path" \
    "$SOURCE_ROOT/$relative_path"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
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

copy_directory_files() {
  local source_dir="$1"
  local target_dir="$2"
  local label_prefix="$3"
  local found=0

  while IFS= read -r -d '' file_path; do
    found=1
    local file_name
    file_name="$(basename "$file_path")"
    copy_file "$file_path" "$target_dir/$file_name" "$label_prefix/$file_name"
  done < <(find "$source_dir" -maxdepth 1 -type f -print0 | sort -z)

  if [ "$found" -eq 0 ]; then
    missing+=("$label_prefix/*")
  fi
}

install_script() {
  local relative_path="$1"
  local source_path="$SOURCE_ROOT/$relative_path"

  if [ -f "$source_path" ]; then
    copy_file "$source_path" "$TARGET_ROOT/$relative_path" "$relative_path"
  else
    missing+=("$relative_path")
  fi
}

copilot_instructions_source="$(resolve_source_file 'copilot-instructions.md' 'copilot-instructions.md' || true)"
prompts_source_dir="$(resolve_source_dir 'prompts' 'prompts' || true)"
workflows_source_dir="$(resolve_source_dir 'workflows' 'workflows' || true)"
root_env_template="$(resolve_root_template '.env.example' || true)"

if [ -n "$copilot_instructions_source" ]; then
  copy_file "$copilot_instructions_source" "$TARGET_ROOT/.github/copilot-instructions.md" ".github/copilot-instructions.md"
else
  missing+=(".github/copilot-instructions.md")
fi

if [ -n "$prompts_source_dir" ]; then
  copy_directory_files "$prompts_source_dir" "$TARGET_ROOT/.github/prompts" ".github/prompts"
else
  missing+=(".github/prompts/*")
fi

if [ -n "$workflows_source_dir" ]; then
  copy_directory_files "$workflows_source_dir" "$TARGET_ROOT/.github/workflows" ".github/workflows"
else
  missing+=(".github/workflows/*")
fi

if [ -n "$root_env_template" ]; then
  copy_file "$root_env_template" "$TARGET_ROOT/.env.example" ".env.example"
else
  missing+=(".env.example")
fi

install_script "scripts/invoke-git-bash.ps1"
install_script "scripts/install-repo-layout/install-repo-layout.sh"
install_script "scripts/install-repo-layout/install-repo-layout.ps1"
install_script "scripts/start/start.sh"
install_script "scripts/start/start.ps1"
install_script "scripts/verified_digest.py"
install_script "scripts/docker-launcher/setup.sh"
install_script "scripts/docker-launcher/setup.ps1"
install_script "scripts/docker-launcher/build.sh"
install_script "scripts/docker-launcher/build.ps1"
install_script "scripts/docker-launcher/launch.sh"
install_script "scripts/docker-launcher/launch.ps1"

echo "=== install-repo-layout.sh ==="
echo "Origen:  $SOURCE_ROOT"
echo "Destino: $TARGET_ROOT"
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
echo "Siguiente paso: ejecuta /start o scripts/start.* dentro del repo destino para completar stack.md y los .env faltantes."