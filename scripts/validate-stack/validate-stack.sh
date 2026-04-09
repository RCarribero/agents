#!/usr/bin/env bash
# validate-stack.sh
# Detecta el stack del proyecto activo desde manifests estándar.
# Si no existe stack.md lo crea con el stack detectado
# y los comandos de test y lint correspondientes.
# Salida: stack detectado + path del stack.md creado o existente

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"

resolve_stack_file() {
  local root="$1"

  if [ -f "$root/stack.md" ]; then
    echo "$root/stack.md"
  elif [ -f "$root/.copilot/stack.md" ]; then
    echo "$root/.copilot/stack.md"
  else
    echo "$root/stack.md"
  fi
}

STACK_FILE="$(resolve_stack_file "$PROJECT_ROOT")"

is_stack_root() {
  local root="$1"
  [ -f "$root/pubspec.yaml" ] || \
  [ -f "$root/package.json" ] || \
  [ -f "$root/requirements.txt" ] || \
  [ -f "$root/pyproject.toml" ] || \
  [ -f "$root/go.mod" ] || \
  [ -f "$root/Cargo.toml" ] || \
  [ -f "$root/pom.xml" ] || \
  [ -f "$root/build.gradle" ]
}

resolve_project_root() {
  local requested_root="$1"
  local -a candidates=()

  if is_stack_root "$requested_root"; then
    echo "$requested_root"
    return 0
  fi

  while IFS= read -r candidate; do
    candidates+=("$candidate")
  done < <(
    find "$requested_root" -maxdepth 3 \
      \( -name pubspec.yaml -o -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml -o -name pom.xml -o -name build.gradle \) \
      -not -path '*/.git/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/venv/*' \
      -not -path '*/.venv/*' \
      -printf '%h\n' | sort -u
  )

  if [ ${#candidates[@]} -eq 1 ]; then
    echo "${candidates[0]}"
    return 0
  fi

  echo "$requested_root"
}

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
    *fastapi*)    echo "python -m ruff check ." ;;
    *python*)     echo "python -m ruff check ." ;;
    *go*)         echo "golangci-lint run" ;;
    *rust*)       echo "cargo clippy" ;;
    *)            echo "# no lint command detected" ;;
  esac
}

EFFECTIVE_ROOT="$(resolve_project_root "$PROJECT_ROOT")"

echo "=== validate-stack.sh ==="
echo "Proyecto: $PROJECT_ROOT"
if [ "$EFFECTIVE_ROOT" != "$PROJECT_ROOT" ]; then
  echo "Subproyecto detectado: $EFFECTIVE_ROOT"
fi
echo ""

stacks_raw=$(detect_stack "$EFFECTIVE_ROOT")
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

## Scope detectado

- Workspace raíz: $PROJECT_ROOT
- Subproyecto con manifests: $EFFECTIVE_ROOT

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
*Regenerar: eliminar este archivo y volver a ejecutar \`scripts/validate-stack/validate-stack.sh\`*
STACKMD
  echo "stack.md creado: $STACK_FILE"
fi

exit 0
