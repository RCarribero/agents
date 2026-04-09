#!/usr/bin/env bash
# sandbox-run.sh — Ejecuta tests/lint en un contenedor Docker aislado.
# Si Docker no está disponible, ejecuta directamente en el host.
#
# Uso:
#   ./scripts/sandbox-run/sandbox-run.sh <project_root> <command> [--json]
#   command: tests | lint
#
# Variables de entorno:
#   SANDBOX_USE_DOCKER=1   Forzar Docker (default: auto-detect)
#   SANDBOX_USE_DOCKER=0   Forzar ejecución directa

set -uo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
COMMAND="${2:-tests}"
OUTPUT_FORMAT="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

USE_DOCKER="${SANDBOX_USE_DOCKER:-}"

# Auto-detect Docker
if [ -z "$USE_DOCKER" ]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    USE_DOCKER=1
  else
    USE_DOCKER=0
  fi
fi

# Seleccionar script de ejecución
case "$COMMAND" in
  tests) SCRIPT="run-tests/run-tests.sh" ;;
  lint)  SCRIPT="run-lint/run-lint.sh" ;;
  *)
    echo "ERROR: comando desconocido '$COMMAND'. Usar: tests | lint" >&2
    exit 1
    ;;
esac

if [ "$USE_DOCKER" = "1" ]; then
  IMAGE="agents-sandbox:latest"

  # Construir imagen si no existe o si el Dockerfile cambió
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Construyendo imagen sandbox..." >&2
    docker build -f "$SCRIPTS_ROOT/Dockerfile.sandbox" -t "$IMAGE" "$SCRIPTS_ROOT/.." >&2
  fi

  docker run --rm \
    --network none \
    --cap-drop ALL \
    --memory 512m \
    --cpus 2.0 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    -v "$PROJECT_ROOT:/workspace:ro" \
    -v "$SCRIPTS_ROOT:/scripts:ro" \
    "$IMAGE" \
    "/scripts/$SCRIPT" "/workspace" "$OUTPUT_FORMAT"
else
  # Ejecución directa en el host
  bash "$SCRIPTS_ROOT/$SCRIPT" "$PROJECT_ROOT" "$OUTPUT_FORMAT"
fi
