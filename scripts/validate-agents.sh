#!/usr/bin/env bash
# validate-agents.sh
# Verifica que cada .agent.md en agents/ tiene:
#   - Frontmatter YAML con 'description' y 'name'
#   - Bloque director_report en el contrato
#   - Sección AUTONOMOUS_LEARNINGS
# Salida: OK por agente, lista de errores al final, exit 1 si hay errores

set -euo pipefail

AGENTS_DIR="${1:-$(dirname "$0")/../agents}"
errors=()
ok_count=0
fail_count=0

check_agent() {
  local file="$1"
  local name
  name=$(basename "$file")
  local file_errors=()

  # 1. Frontmatter: debe existir --- ... --- al inicio
  if ! head -1 "$file" | grep -q "^---"; then
    file_errors+=("frontmatter ausente")
  else
    # Verificar campo 'name'
    if ! awk '/^---/{f++} f==1{print}' "$file" | grep -q "^name:"; then
      file_errors+=("campo 'name' ausente en frontmatter")
    fi
    # Verificar campo 'description'
    if ! awk '/^---/{f++} f==1{print}' "$file" | grep -q "^description:"; then
      file_errors+=("campo 'description' ausente en frontmatter")
    fi
  fi

  # 2. Bloque director_report
  if ! grep -q "<director_report>" "$file"; then
    file_errors+=("bloque <director_report> ausente")
  fi

  # 3. Sección AUTONOMOUS_LEARNINGS
  if ! grep -q "AUTONOMOUS_LEARNINGS" "$file"; then
    file_errors+=("sección AUTONOMOUS_LEARNINGS ausente")
  fi

  if [ ${#file_errors[@]} -eq 0 ]; then
    echo "OK   $name"
    ok_count=$((ok_count + 1))
  else
    echo "FAIL $name"
    for e in "${file_errors[@]}"; do
      echo "     → $e"
      errors+=("$name: $e")
    done
    fail_count=$((fail_count + 1))
  fi
}

echo "=== validate-agents.sh ==="
echo "Directorio: $AGENTS_DIR"
echo ""

if [ ! -d "$AGENTS_DIR" ]; then
  echo "ERROR: directorio '$AGENTS_DIR' no encontrado"
  exit 1
fi

while IFS= read -r -d '' agent_file; do
  check_agent "$agent_file"
done < <(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -print0 | sort -z)

echo ""
echo "---"
echo "Resumen: $ok_count OK, $fail_count FAIL"

if [ ${#errors[@]} -gt 0 ]; then
  echo ""
  echo "Errores encontrados:"
  for e in "${errors[@]}"; do
    echo "  - $e"
  done
  exit 1
fi

exit 0
