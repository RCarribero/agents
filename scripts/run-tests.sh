#!/usr/bin/env bash
# run-tests.sh — Ejecuta los tests del proyecto en el entorno sandbox.
# Detecta el stack automáticamente y retorna stdout/stderr + exit code estructurados.
#
# Uso:
#   ./scripts/run-tests.sh [PROJECT_ROOT] [--json]
#
# Salida normal:  stdout del runner + resumen final
# Salida --json:  JSON { success, exit_code, stdout, stderr, duration_s, stack }

set -uo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
OUTPUT_FORMAT="${2:-}"

START_TIME=$(date +%s%3N)

# Detectar stack
detect_stack() {
  local root="$1"
  if [ -f "$root/pubspec.yaml" ]; then echo "flutter"
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
get_test_cmd() {
  case "$1" in
    flutter)  echo "flutter test --reporter=compact" ;;
    nextjs)   echo "npm test -- --passWithNoTests --watchAll=false" ;;
    node)     echo "npm test -- --passWithNoTests" ;;
    python)   echo "python -m pytest -q --tb=short" ;;
    go)       echo "go test ./... -v" ;;
    rust)     echo "cargo test" ;;
    *)        echo "" ;;
  esac
}

TEST_CMD=$(get_test_cmd "$STACK")

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
$TEST_CMD >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?

END_TIME=$(date +%s%3N)
DURATION=$(( (END_TIME - START_TIME) / 1000 ))

STDOUT_CONTENT=$(<"$STDOUT_FILE")
STDERR_CONTENT=$(<"$STDERR_FILE")

if [ "$OUTPUT_FORMAT" = "--json" ]; then
  # Escapar para JSON válido
  STDOUT_JSON=$(echo "$STDOUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$STDOUT_CONTENT\"")
  STDERR_JSON=$(echo "$STDERR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$STDERR_CONTENT\"")
  SUCCESS=$( [ "$EXIT_CODE" -eq 0 ] && echo "true" || echo "false" )
  echo "{\"success\":$SUCCESS,\"exit_code\":$EXIT_CODE,\"stdout\":$STDOUT_JSON,\"stderr\":$STDERR_JSON,\"duration_s\":$DURATION,\"stack\":\"$STACK\"}"
else
  echo "=== run-tests.sh | stack: $STACK | cmd: $TEST_CMD ==="
  echo ""
  echo "$STDOUT_CONTENT"
  [ -n "$STDERR_CONTENT" ] && echo "--- stderr ---" && echo "$STDERR_CONTENT"
  echo ""
  echo "--- exit_code: $EXIT_CODE | duration: ${DURATION}s ---"
fi

exit "$EXIT_CODE"
