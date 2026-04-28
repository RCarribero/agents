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

copy_dir_files_if_missing() {
  local source_dir="$1"
  local target_dir="$2"
  local label_prefix="$3"
  local name_pattern="${4:-*}"

  if [ ! -d "$source_dir" ]; then
    missing_templates+=("$label_prefix/*")
    return 0
  fi

  local found=0
  local source_file target_file file_name
  while IFS= read -r source_file; do
    found=1
    file_name="$(basename "$source_file")"
    target_file="$target_dir/$file_name"
    copy_if_missing "$source_file" "$target_file" "$label_prefix/$file_name"
  done < <(find "$source_dir" -maxdepth 1 -type f -name "$name_pattern" | sort)

  if [ "$found" -eq 0 ]; then
    missing_templates+=("$label_prefix/*")
  fi
}

resolve_copilot_instructions_source() {
  # Archivo canónico: .github/copilot-instructions.md (GitHub Copilot lo lee nativamente).
  # El fallback a copilot-instructions.md raíz fue eliminado (FIX-002).
  for candidate in \
    "$SOURCE_ROOT/repo-templates/.github/copilot-instructions.md" \
    "$SOURCE_ROOT/.github/copilot-instructions.md"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

# Hook-related functions removed: hooks are global only, installed via install-copilot-layout, not /start

detect_stack_file() {
  if [ -f "$PROJECT_ROOT/stack.md" ]; then
    echo "$PROJECT_ROOT/stack.md"
  elif [ -f "$PROJECT_ROOT/.copilot/stack.md" ]; then
    echo "$PROJECT_ROOT/.copilot/stack.md"
  fi
}

resolve_stack_target() {
  if [ -f "$PROJECT_ROOT/.copilot/stack.md" ]; then
    echo "$PROJECT_ROOT/.copilot/stack.md"
  else
    echo "$PROJECT_ROOT/stack.md"
  fi
}

is_stack_root() {
  local root="$1"
  [ -f "$root/pubspec.yaml" ] || \
  [ -f "$root/package.json" ] || \
  [ -f "$root/requirements.txt" ] || \
  [ -f "$root/pyproject.toml" ] || \
  [ -f "$root/go.mod" ] || \
  [ -f "$root/Cargo.toml" ] || \
  [ -f "$root/pom.xml" ] || \
  [ -f "$root/build.gradle" ] || \
  [ -d "$root/agents" ]
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

  [ -f "$root/pubspec.yaml" ] && stacks+=("flutter")
  [ -f "$root/package.json" ] && stacks+=("node")
  if [ -f "$root/requirements.txt" ] || [ -f "$root/pyproject.toml" ]; then
    stacks+=("python")
  fi
  [ -f "$root/go.mod" ] && stacks+=("go")
  [ -f "$root/Cargo.toml" ] && stacks+=("rust")
  [ -f "$root/pom.xml" ] && stacks+=("java-maven")
  [ -f "$root/build.gradle" ] && stacks+=("java-gradle")

  if [ -d "$root/agents" ] && [ -d "$root/scripts" ] && [ -d "$root/.github" ]; then
    stacks+=("toolkit")
  fi

  if [[ " ${stacks[*]} " =~ " node " ]]; then
    if grep -q '"next"' "$root/package.json" 2>/dev/null; then
      stacks+=("nextjs")
    elif grep -q '"react"' "$root/package.json" 2>/dev/null; then
      stacks+=("react")
    fi
  fi

  if [[ " ${stacks[*]} " =~ " python " ]]; then
    if grep -q 'fastapi' "$root/requirements.txt" 2>/dev/null || \
       grep -q 'fastapi' "$root/pyproject.toml" 2>/dev/null; then
      stacks+=("fastapi")
    fi
  fi

  if [ ${#stacks[@]} -eq 0 ]; then
    stacks+=("unknown")
  fi

  printf '%s\n' "${stacks[@]}"
}

get_test_cmd() {
  local stack="$1"
  case "$stack" in
    *flutter*)    echo "flutter test" ;;
    *nextjs*)     echo "pnpm test -- --passWithNoTests" ;;
    *react*)      echo "pnpm test -- --passWithNoTests" ;;
    *node*)       echo "pnpm test" ;;
    *fastapi*)    echo "pytest" ;;
    *python*)     echo "pytest" ;;
    *go*)         echo "go test ./..." ;;
    *rust*)       echo "cargo test" ;;
    *toolkit*)    echo "# usa el flujo del swarm y las verificaciones del proyecto activo" ;;
    *)            echo "# define manualmente el comando de tests para este proyecto" ;;
  esac
}

get_lint_cmd() {
  local stack="$1"
  case "$stack" in
    *flutter*)    echo "flutter analyze" ;;
    *nextjs*)     echo "pnpm lint" ;;
    *react*)      echo "pnpm lint" ;;
    *node*)       echo "pnpm lint" ;;
    *fastapi*)    echo "python -m ruff check ." ;;
    *python*)     echo "python -m ruff check ." ;;
    *go*)         echo "golangci-lint run" ;;
    *rust*)       echo "cargo clippy" ;;
    *toolkit*)    echo "# usa las verificaciones nativas del proyecto activo" ;;
    *)            echo "# define manualmente el comando de lint para este proyecto" ;;
  esac
}

ensure_stack_file() {
  local effective_root stack_target stacks_raw all_stacks test_cmd lint_cmd
  local -a stacks=()

  effective_root="$(resolve_project_root "$PROJECT_ROOT")"
  stack_target="$(resolve_stack_target)"

  if [ -f "$stack_target" ]; then
    return 0
  fi

  while IFS= read -r stack_name; do
    if [ -n "$stack_name" ]; then
      stacks+=("$stack_name")
    fi
  done < <(detect_stack "$effective_root")

  all_stacks="$(printf '%s, ' "${stacks[@]}")"
  all_stacks="${all_stacks%, }"
  stacks_raw="${stacks[*]}"
  test_cmd="$(get_test_cmd "$stacks_raw")"
  lint_cmd="$(get_lint_cmd "$stacks_raw")"

  mkdir -p "$(dirname "$stack_target")"
  cat > "$stack_target" <<STACKMD
# Stack del Proyecto

**Detectado automáticamente por start.sh** — $(date +%Y-%m-%d)

## Scope detectado

- Workspace raíz: $PROJECT_ROOT
- Subproyecto con manifests: $effective_root

## Stack activo

\`\`\`
$all_stacks
\`\`\`

## Comandos orientativos

| Acción | Comando |
|--------|---------|
| Tests  | \`$test_cmd\` |
| Lint   | \`$lint_cmd\` |

## Señales detectadas

$(for stack_name in "${stacks[@]}"; do echo "- $stack_name"; done)

---
*Regenerar: eliminar este archivo y volver a ejecutar \`scripts/start/start.sh\`*
STACKMD
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

# Hook installation removed: hooks are global only (~/.copilot/hooks/orchestra.json via install-copilot-layout), not workspace

stack_file_before="$(detect_stack_file || true)"
ensure_stack_file
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
