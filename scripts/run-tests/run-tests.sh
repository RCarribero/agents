#!/usr/bin/env bash
# run-tests.sh — Ejecuta los tests del proyecto en el entorno sandbox.
# Detecta el stack automáticamente y retorna stdout/stderr + exit code estructurados.
#
# Uso:
#   ./scripts/run-tests/run-tests.sh [PROJECT_ROOT] [--json]
#
# Salida normal:  stdout del runner + resumen final
# Salida --json:  JSON { success, exit_code, stdout, stderr, duration_s, stack }

set -uo pipefail

PROJECT_ROOT_INPUT="${1:-$(pwd)}"
OUTPUT_FORMAT="${2:-}"

START_TIME=$(date +%s%3N)

is_toolkit_root() {
  local root="$1"
  [ -f "$root/stack.md" ] && \
  [ -d "$root/agents" ] && \
  [ -d "$root/scripts" ] && \
  [ -f "$root/scripts/run_eval_gate.py" ]
}

is_stack_root() {
  local root="$1"
  [ -f "$root/pubspec.yaml" ] || \
  [ -f "$root/package.json" ] || \
  [ -f "$root/requirements.txt" ] || \
  [ -f "$root/pyproject.toml" ] || \
  [ -f "$root/go.mod" ] || \
  [ -f "$root/Cargo.toml" ]
}

resolve_project_root() {
  local requested_root="$1"
  local -a candidates=()

  if is_toolkit_root "$requested_root"; then
    echo "$requested_root"
    return 0
  fi

  if is_stack_root "$requested_root"; then
    echo "$requested_root"
    return 0
  fi

  while IFS= read -r candidate; do
    candidates+=("$candidate")
  done < <(
    find "$requested_root" -maxdepth 3 \
      \( -name pubspec.yaml -o -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name go.mod -o -name Cargo.toml \) \
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

json_escape_file() {
  local file_path="$1"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json, pathlib, sys; print(json.dumps(pathlib.Path(sys.argv[1]).read_bytes().decode('utf-8', errors='replace')))" "$file_path"
  elif command -v python >/dev/null 2>&1; then
    python -c "import json, pathlib, sys; print(json.dumps(pathlib.Path(sys.argv[1]).read_bytes().decode('utf-8', errors='replace')))" "$file_path"
  else
    printf '""'
  fi
}

PROJECT_ROOT="$(resolve_project_root "$PROJECT_ROOT_INPUT")"

resolve_python_cmd() {
  if command -v python >/dev/null 2>&1; then
    echo "python"
  elif command -v python3 >/dev/null 2>&1; then
    echo "python3"
  else
    echo ""
  fi
}

# Detectar stack
detect_stack() {
  local root="$1"
  if is_toolkit_root "$root"; then echo "toolkit"
  elif [ -f "$root/pubspec.yaml" ]; then echo "flutter"
  elif [ -f "$root/package.json" ] && grep -q '"next"' "$root/package.json" 2>/dev/null; then echo "nextjs"
  elif [ -f "$root/package.json" ]; then echo "node"
  elif [ -f "$root/requirements.txt" ] || [ -f "$root/pyproject.toml" ]; then echo "python"
  elif [ -f "$root/go.mod" ]; then echo "go"
  elif [ -f "$root/Cargo.toml" ]; then echo "rust"
  else echo "unknown"
  fi
}

STACK=$(detect_stack "$PROJECT_ROOT")

# Seleccionar comando de test
describe_test_cmd() {
  case "$1" in
    toolkit)  echo "python ./scripts/run_eval_gate.py --root . --report-file -" ;;
    flutter)  echo "flutter test --reporter=compact" ;;
    nextjs)   echo "npm test -- --passWithNoTests --watchAll=false" ;;
    node)     echo "npm test -- --passWithNoTests" ;;
    python)   echo "python -m pytest -q --tb=short" ;;
    go)       echo "go test ./... -v" ;;
    rust)     echo "cargo test" ;;
    *)        echo "" ;;
  esac
}

run_test_cmd() {
  case "$1" in
    toolkit)
      local python_cmd
      python_cmd="$(resolve_python_cmd)"
      if [ -z "$python_cmd" ]; then
        echo "ERROR: python/python3 no disponible para ejecutar run_eval_gate.py" >&2
        return 127
      fi
      "$python_cmd" ./scripts/run_eval_gate.py --root . --report-file -
      ;;
    flutter)
      flutter test --reporter=compact
      ;;
    nextjs)
      npm test -- --passWithNoTests --watchAll=false
      ;;
    node)
      npm test -- --passWithNoTests
      ;;
    python)
      python -m pytest -q --tb=short
      ;;
    go)
      go test ./... -v
      ;;
    rust)
      cargo test
      ;;
    *)
      return 1
      ;;
  esac
}

TEST_CMD=$(describe_test_cmd "$STACK")

if [ -z "$TEST_CMD" ]; then
  MSG="ERROR: No se detectó stack compatible en '$PROJECT_ROOT'"
  if [ "$OUTPUT_FORMAT" = "--json" ]; then
    echo "{\"success\":false,\"exit_code\":1,\"stdout\":\"\",\"stderr\":\"$MSG\",\"duration_s\":0,\"stack\":\"unknown\"}"
  else
    echo "$MSG" >&2
  fi
  exit 1
fi

# Ejecutar tests
STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

cd "$PROJECT_ROOT"
run_test_cmd "$STACK" >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?

END_TIME=$(date +%s%3N)
DURATION=$(( (END_TIME - START_TIME) / 1000 ))

STDOUT_CONTENT=$(<"$STDOUT_FILE")
STDERR_CONTENT=$(<"$STDERR_FILE")

if [ "$OUTPUT_FORMAT" = "--json" ]; then
  # Escapar para JSON válido
  STDOUT_JSON=$(json_escape_file "$STDOUT_FILE")
  STDERR_JSON=$(json_escape_file "$STDERR_FILE")
  SUCCESS=$( [ "$EXIT_CODE" -eq 0 ] && echo "true" || echo "false" )
  echo "{\"success\":$SUCCESS,\"exit_code\":$EXIT_CODE,\"stdout\":$STDOUT_JSON,\"stderr\":$STDERR_JSON,\"duration_s\":$DURATION,\"stack\":\"$STACK\"}"
else
  echo "=== run-tests.sh | stack: $STACK | root: $PROJECT_ROOT | cmd: $TEST_CMD ==="
  echo ""
  echo "$STDOUT_CONTENT"
  [ -n "$STDERR_CONTENT" ] && echo "--- stderr ---" && echo "$STDERR_CONTENT"
  echo ""
  echo "--- exit_code: $EXIT_CODE | duration: ${DURATION}s ---"
fi

exit "$EXIT_CODE"
