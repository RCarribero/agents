#!/usr/bin/env bash
# start.sh — Bootstrap de configuración del proyecto.
# Usa el instalador repo-local del toolkit actual y crea stack.md y archivos .env
# si faltan, sin sobreescribir existentes.

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

created=()
existing=()
missing_templates=()

copy_if_missing() {
  local source="$1"
  local target="$2"
  local label="$3"

  if [ -f "$target" ]; then
    existing+=("$label")
  elif [ -f "$source" ]; then
    cp "$source" "$target"
    created+=("$label")
  else
    missing_templates+=("$label")
  fi
}

if [ -f "$SCRIPTS_ROOT/install-repo-layout/install-repo-layout.sh" ]; then
  bash "$SCRIPTS_ROOT/install-repo-layout/install-repo-layout.sh" "$PROJECT_ROOT"
else
  missing_templates+=("scripts/install-repo-layout/install-repo-layout.sh")
fi

bash "$SCRIPTS_ROOT/validate-stack/validate-stack.sh" "$PROJECT_ROOT"
copy_if_missing "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env" ".env"
copy_if_missing "$PROJECT_ROOT/agents/api/.env.example" "$PROJECT_ROOT/agents/api/.env" "agents/api/.env"

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
echo "Siguiente paso: completar los valores reales en .env y agents/api/.env si fueron creados. Si acabas de instalar los prompts globales, recarga VS Code para verlos en cualquier workspace."
