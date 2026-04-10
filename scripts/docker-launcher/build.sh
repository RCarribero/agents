#!/usr/bin/env bash
# docker-launcher/build.sh — Construye las imágenes Docker del proyecto.
#
# Uso: ./build.sh [build|rebuild] [--no-cache] [--target <stage>] [--service <nombre>]
#   build (default)      Construye las imágenes (usa caché si existe)
#   rebuild              Para contenedores, elimina imágenes y reconstruye desde cero
#   --no-cache           Fuerza rebuild sin caché de capas
#   --target <stage>     Construye solo hasta ese stage de Dockerfile (ej: builder)
#   --service <nombre>   Aplica la acción solo a ese servicio de docker-compose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NO_CACHE=""
TARGET_STAGE=""
SERVICE_FILTER=""

# ── Parseo de acción y argumentos ────────────────────────────────────────────
ACTION="build"
if [[ "${1:-}" == "rebuild" || "${1:-}" == "build" ]]; then
  ACTION="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache)          NO_CACHE="--no-cache"; shift ;;
    --target)            TARGET_STAGE="--target $2"; shift 2 ;;
    --service)           SERVICE_FILTER="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

# rebuild implica siempre --no-cache
[ "$ACTION" = "rebuild" ] && NO_CACHE="--no-cache"

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[build]${NC} $*"; }
success() { echo -e "${GREEN}[build]${NC} $*"; }
warn()    { echo -e "${YELLOW}[build][WARN]${NC} $*"; }
error()   { echo -e "${RED}[build][ERROR]${NC} $*" >&2; exit 1; }

cd "$PROJECT_ROOT"

# ── 1. Verificar que existan los archivos clave ───────────────────────────────
[ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ] && \
  error "No se encontró Dockerfile ni docker-compose.yml en $PROJECT_ROOT"

# ── 2. Cargar .env si existe ─────────────────────────────────────────────────
if [ -f ".env" ]; then
  set -a; source ".env"; set +a
  info ".env cargado."
else
  warn "No se encontró .env. Ejecuta ./setup.sh primero si es necesario."
fi

# ── 3. Detectar nombre de imagen ──────────────────────────────────────────────
IMAGE_NAME="${IMAGE_NAME:-$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# ── 4. Seleccionar modo de build ──────────────────────────────────────────────
if [ -f "docker-compose.yml" ]; then
  # Detectar Compose v2 vs v1
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
  elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
  else
    error "Docker Compose no encontrado."
  fi

  # ── Rebuild: parar contenedores y borrar imágenes antes de reconstruir ─────────
  if [ "$ACTION" = "rebuild" ]; then
    TARGET_DESC="${SERVICE_FILTER:-todos los servicios}"
    warn "Rebuild: parando y eliminando imágenes de ${TARGET_DESC}..."
    # shellcheck disable=SC2086
    $COMPOSE stop $SERVICE_FILTER 2>/dev/null || true
    # shellcheck disable=SC2086
    $COMPOSE rm -f $SERVICE_FILTER 2>/dev/null || true
    # Eliminar imágenes locales del/los servicio/s
    if [ -n "$SERVICE_FILTER" ]; then
      IMG=$($COMPOSE images -q "$SERVICE_FILTER" 2>/dev/null || true)
    else
      IMG=$($COMPOSE images -q 2>/dev/null || true)
    fi
    if [ -n "$IMG" ]; then
      # shellcheck disable=SC2086
      docker rmi -f $IMG 2>/dev/null || true
      info "Imágenes anteriores eliminadas."
    fi
    info "Comenzando rebuild sin caché..."
  fi

  info "Construyendo con Compose (${COMPOSE})..."
  BUILD_ARGS="build"
  [ -n "$NO_CACHE" ] && BUILD_ARGS="$BUILD_ARGS --no-cache"
  [ -n "$SERVICE_FILTER" ] && BUILD_ARGS="$BUILD_ARGS $SERVICE_FILTER"

  BUILD_START=$(date +%s)
  # shellcheck disable=SC2086
  $COMPOSE $BUILD_ARGS
  BUILD_END=$(date +%s)

else
  # Build directo con docker build
  if [ "$ACTION" = "rebuild" ]; then
    warn "Rebuild: eliminando imagen ${FULL_IMAGE}..."
    docker rmi -f "${FULL_IMAGE}" 2>/dev/null || true
    info "Imagen eliminada. Comenzando rebuild sin caché..."
  fi

  info "Construyendo imagen ${FULL_IMAGE} ..."
  BUILD_ARGS="build -t ${FULL_IMAGE} ${NO_CACHE} ${TARGET_STAGE} ."
  BUILD_START=$(date +%s)
  # shellcheck disable=SC2086
  docker $BUILD_ARGS
  BUILD_END=$(date +%s)
fi

ELAPSED=$((BUILD_END - BUILD_START))
success "Build completado en ${ELAPSED}s. Siguiente paso: ./launch.sh"
