#!/usr/bin/env bash
# run-lint.sh — Ejecuta el linter del proyecto y retorna resultado estructurado.
#
# Uso:
#   ./scripts/run-lint.sh [PROJECT_ROOT] [--json]

set -uo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
OUTPUT_FORMAT="${2:-}"

START_TIME=$(date +%s%3N)

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

get_lint_cmd() {
  case "$1" in
    flutter)  echo "flutter analyze --no-fatal-infos" ;;
    nextjs)   echo "npm run lint" ;;
    node)     echo "npm run lint" ;;
    python)   echo "ruff check . --output-format=json" ;;
    go)       echo "go vet ./..." ;;
    rust)     echo "cargo clippy -- -D warnings" ;;
    *)        echo "" ;;
  esac
}

LINT_CMD=$(get_lint_cmd "$STACK")

if [ -z "$LINT_CMD" ]; then
  MSG="ERROR: No se detectó stack compatible en '$PROJECT_ROOT'"
  [ "$OUTPUT_FORMAT" = "--json" ] && \
    echo "{\"success\":false,\"exit_code\":1,\"stdout\":\"\",\"stderr\":\"$MSG\",\"duration_s\":0,\"stack\":\"unknown\"}" || \
    echo "$MSG" >&2
  exit 1
fi

STDOUT_FILE=$(mktemp)
STDERR_FILE=$(mktemp)
trap 'rm -f "$STDOUT_FILE" "$STDERR_FILE"' EXIT

cd "$PROJECT_ROOT"
$LINT_CMD >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?

END_TIME=$(date +%s%3N)
DURATION=$(( (END_TIME - START_TIME) / 1000 ))
STDOUT_CONTENT=$(<"$STDOUT_FILE")
STDERR_CONTENT=$(<"$STDERR_FILE")

if [ "$OUTPUT_FORMAT" = "--json" ]; then
  STDOUT_JSON=$(echo "$STDOUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"\"")
  STDERR_JSON=$(echo "$STDERR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"\"")
  SUCCESS=$( [ "$EXIT_CODE" -eq 0 ] && echo "true" || echo "false" )
  echo "{\"success\":$SUCCESS,\"exit_code\":$EXIT_CODE,\"stdout\":$STDOUT_JSON,\"stderr\":$STDERR_JSON,\"duration_s\":$DURATION,\"stack\":\"$STACK\"}"
else
  echo "=== run-lint.sh | stack: $STACK | cmd: $LINT_CMD ==="
  echo "$STDOUT_CONTENT"
  [ -n "$STDERR_CONTENT" ] && echo "--- stderr ---" && echo "$STDERR_CONTENT"
  echo "--- exit_code: $EXIT_CODE | duration: ${DURATION}s ---"
fi

exit "$EXIT_CODE"
