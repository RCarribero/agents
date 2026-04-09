#!/usr/bin/env bash
# validate-stack.sh
# Detecta el stack del proyecto activo desde manifests estándar.
# Si no existe .copilot/stack.md lo crea con el stack detectado
# y los comandos de test y lint correspondientes.
# Salida: stack detectado + path del stack.md creado o existente

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
STACK_FILE="$PROJECT_ROOT/.copilot/stack.md"

detect_stack() {
  local root="$1"
  local stacks=()

  [ -f "$root/pubspec.yaml" ]    && stacks+=("flutter")
  [ -f "$root/package.json" ]    && stacks+=("node")
  [ -f "$root/requirements.txt" ] || [ -f "$root/pyproject.toml" ] && stacks+=("python")
  [ -f "$root/go.mod" ]          && stacks+=("go")
  [ -f "$root/Cargo.toml" ]      && stacks+=("rust")
  [ -f "$root/pom.xml" ]         && stacks+=("java-maven")
  [ -f "$root/build.gradle" ]    && stacks+=("java-gradle")

  # Detectar subtipos
  if [[ " ${stacks[*]} " =~ " node " ]]; then
    if grep -q "\"next\"" "$root/package.json" 2>/dev/null; then
      stacks+=("nextjs")
    elif grep -q "\"react\"" "$root/package.json" 2>/dev/null; then
      stacks+=("react")
    fi
  fi

  if [[ " ${stacks[*]} " =~ " python " ]]; then
    if grep -q "fastapi" "$root/requirements.txt" 2>/dev/null || \
       grep -q "fastapi" "$root/pyproject.toml" 2>/dev/null; then
      stacks+=("fastapi")
    fi
  fi

  echo "${stacks[*]}"
}

get_test_cmd() {
  local stack="$1"
  case "$stack" in
    *flutter*)    echo "flutter test" ;;
    *nextjs*)     echo "npm test -- --passWithNoTests" ;;
    *react*)      echo "npm test -- --passWithNoTests" ;;
    *node*)       echo "npm test" ;;
    *fastapi*)    echo "pytest" ;;
    *python*)     echo "pytest" ;;
    *go*)         echo "go test ./..." ;;
    *rust*)       echo "cargo test" ;;
    *)            echo "# no test command detected" ;;
  esac
}

get_lint_cmd() {
  local stack="$1"
  case "$stack" in
    *flutter*)    echo "flutter analyze" ;;
    *nextjs*)     echo "npm run lint" ;;
    *react*)      echo "npm run lint" ;;
    *node*)       echo "npm run lint" ;;
    *fastapi*)    echo "ruff check . && mypy ." ;;
    *python*)     echo "ruff check ." ;;
    *go*)         echo "golangci-lint run" ;;
    *rust*)       echo "cargo clippy" ;;
    *)            echo "# no lint command detected" ;;
  esac
}

echo "=== validate-stack.sh ==="
echo "Proyecto: $PROJECT_ROOT"
echo ""

stacks_raw=$(detect_stack "$PROJECT_ROOT")
read -ra stacks <<< "$stacks_raw"

if [ ${#stacks[@]} -eq 0 ]; then
  echo "WARN: No se detectó ningún stack conocido en '$PROJECT_ROOT'"
  echo "      Asegúrate de apuntar al directorio correcto del proyecto."
  exit 0
fi

primary_stack="${stacks[0]}"
all_stacks=$(IFS=", "; echo "${stacks[*]}")
test_cmd=$(get_test_cmd "$stacks_raw")
lint_cmd=$(get_lint_cmd "$stacks_raw")

echo "Stack detectado: $all_stacks"
echo "Test command:    $test_cmd"
echo "Lint command:    $lint_cmd"
echo ""

if [ -f "$STACK_FILE" ]; then
  echo "stack.md ya existe: $STACK_FILE"
  echo "(no se sobreescribe — elimina el archivo para regenerar)"
else
  mkdir -p "$(dirname "$STACK_FILE")"
  cat > "$STACK_FILE" <<STACKMD
# Stack del Proyecto

**Detectado automáticamente por validate-stack.sh** — $(date +%Y-%m-%d)

## Stack activo

\`\`\`
$all_stacks
\`\`\`

## Comandos

| Acción | Comando |
|--------|---------|
| Tests  | \`$test_cmd\` |
| Lint   | \`$lint_cmd\` |

## Manifests detectados

$(for s in "${stacks[@]}"; do echo "- $s"; done)

---
*Regenerar: eliminar este archivo y volver a ejecutar \`scripts/validate-stack.sh\`*
STACKMD
  echo "stack.md creado: $STACK_FILE"
fi

exit 0
