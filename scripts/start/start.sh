#!/usr/bin/env bash
# start.sh — Bootstrap mínimo del proyecto.
# Crea copilot-instructions y stack.md si faltan e intenta descargar skills con
# autoskills sin materializar el layout completo del toolkit en el repo destino.

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="$(cd "$SCRIPTS_ROOT/.." && pwd)"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

created=()
existing=()
missing_templates=()
SKILLS_STATUS="SKIPPED"
SKILLS_DETAILS="autoskills no ejecutado"

copy_if_missing() {
  local source="$1"
  local target="$2"
  local label="$3"

  if [ -f "$target" ]; then
    existing+=("$label")
  elif [ -f "$source" ]; then
    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    created+=("$label")
  else
    missing_templates+=("$label")
  fi
}

resolve_copilot_instructions_source() {
  for candidate in \
    "$SOURCE_ROOT/repo-templates/.github/copilot-instructions.md" \
    "$SOURCE_ROOT/.github/copilot-instructions.md" \
    "$SOURCE_ROOT/copilot-instructions.md"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

detect_stack_file() {
  if [ -f "$PROJECT_ROOT/stack.md" ]; then
    echo "$PROJECT_ROOT/stack.md"
  elif [ -f "$PROJECT_ROOT/.copilot/stack.md" ]; then
    echo "$PROJECT_ROOT/.copilot/stack.md"
  fi
}

run_autoskills() {
  local log_file
  log_file="$(mktemp)"

  if ! command -v npx >/dev/null 2>&1; then
    SKILLS_STATUS="SKIPPED"
    SKILLS_DETAILS="npx no disponible"
    rm -f "$log_file"
    return 0
  fi

  if (cd "$PROJECT_ROOT" && npx --yes autoskills --yes) >"$log_file" 2>&1; then
    SKILLS_STATUS="OK"
    SKILLS_DETAILS="autoskills ejecutado"
  else
    local tail_output
    tail_output="$(tail -n 5 "$log_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    SKILLS_STATUS="WARN"
    SKILLS_DETAILS="${tail_output:-autoskills devolvió error}"
  fi

  rm -f "$log_file"
}

copilot_instructions_source="$(resolve_copilot_instructions_source || true)"
if [ -n "$copilot_instructions_source" ]; then
  copy_if_missing "$copilot_instructions_source" "$PROJECT_ROOT/.github/copilot-instructions.md" ".github/copilot-instructions.md"
else
  missing_templates+=(".github/copilot-instructions.md")
fi

stack_file_before="$(detect_stack_file || true)"
bash "$SCRIPTS_ROOT/validate-stack/validate-stack.sh" "$PROJECT_ROOT"
stack_file_after="$(detect_stack_file || true)"
if [ -n "$stack_file_after" ]; then
  if [ -n "$stack_file_before" ]; then
    existing+=("stack.md")
  else
    created+=("stack.md")
  fi
fi

run_autoskills

echo ""
echo "=== start.sh ==="

echo "Archivos creados:"
if [ ${#created[@]} -eq 0 ]; then
  echo "  - ninguno"
else
  for item in "${created[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Archivos existentes:"
if [ ${#existing[@]} -eq 0 ]; then
  echo "  - ninguno"
else
  for item in "${existing[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Plantillas ausentes:"
if [ ${#missing_templates[@]} -eq 0 ]; then
  echo "  - ninguna"
else
  for item in "${missing_templates[@]}"; do
    echo "  - $item"
  done
fi

echo ""
echo "Skills:"
echo "  - estado: $SKILLS_STATUS"
echo "  - detalle: $SKILLS_DETAILS"

echo ""
echo "Siguiente paso: revisar .github/copilot-instructions.md y stack.md. Si autoskills estuvo disponible, verifica los skills instalados en el workspace."
