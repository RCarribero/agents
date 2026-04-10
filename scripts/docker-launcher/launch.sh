#!/usr/bin/env bash
# docker-launcher/launch.sh — Lanza los contenedores Docker del proyecto.
#
# Uso: ./launch.sh [up|down|restart|logs|status] [--detach] [--service <nombre>]
#   up              Levanta los contenedores (default)
#   down            Para y elimina los contenedores (mantiene volúmenes)
#   down --volumes  Para y elimina contenedores + volúmenes (¡destructivo!)
#   restart         Reinicia los contenedores
#   logs            Muestra los logs (sigue en tiempo real)
#   status          Muestra el estado de los contenedores
#   --detach        Corre en segundo plano (default en 'up')
#   --service       Aplica la acción solo a ese servicio

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTION="${1:-up}"
DETACH="--detach"
VOLUMES_FLAG=""
SERVICE_FILTER=""

# ── Parseo de argumentos adicionales ─────────────────────────────────────────
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-detach)   DETACH=""; shift ;;
    --volumes)     VOLUMES_FLAG="--volumes"; shift ;;
    --service)     SERVICE_FILTER="$2"; shift 2 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 1 ;;
  esac
done

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[launch]${NC} $*"; }
success() { echo -e "${GREEN}[launch]${NC} $*"; }
warn()    { echo -e "${YELLOW}[launch][WARN]${NC} $*"; }
error()   { echo -e "${RED}[launch][ERROR]${NC} $*" >&2; exit 1; }

cd "$PROJECT_ROOT"

# ── Detectar Compose ──────────────────────────────────────────────────────────
if docker compose version &>/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE="docker-compose"
else
  error "Docker Compose no encontrado."
fi

# ── Cargar .env ───────────────────────────────────────────────────────────────
if [ -f ".env" ]; then
  set -a; source ".env"; set +a
fi

IMAGE_NAME="${IMAGE_NAME:-$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')}"
APP_PORT="${APP_PORT:-3000}"

# ── Ejecutar la acción ────────────────────────────────────────────────────────
case "$ACTION" in
  up)
    info "Levantando contenedores${SERVICE_FILTER:+ (servicio: $SERVICE_FILTER)}..."
    ARGS="up ${DETACH} ${SERVICE_FILTER}"
    # shellcheck disable=SC2086
    $COMPOSE $ARGS
    if [ -n "$DETACH" ]; then
      success "Contenedores activos. App disponible en http://localhost:${APP_PORT}"
      info "  Ver logs:    ./launch.sh logs"
      info "  Estado:      ./launch.sh status"
      info "  Detener:     ./launch.sh down"
    fi
    ;;

  down)
    if [ -n "$VOLUMES_FLAG" ]; then
      warn "Se eliminarán los volúmenes de datos. Esta acción es IRREVERSIBLE."
      read -r -p "¿Confirmar? [y/N] " CONFIRM
      [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Cancelado."; exit 0; }
    fi
    info "Deteniendo contenedores..."
    $COMPOSE down ${VOLUMES_FLAG} ${SERVICE_FILTER}
    success "Contenedores detenidos."
    ;;

  restart)
    info "Reiniciando contenedores${SERVICE_FILTER:+ (servicio: $SERVICE_FILTER)}..."
    $COMPOSE restart ${SERVICE_FILTER}
    success "Contenedores reiniciados."
    ;;

  logs)
    info "Mostrando logs (Ctrl+C para salir)..."
    $COMPOSE logs --follow --tail=100 ${SERVICE_FILTER}
    ;;

  status)
    $COMPOSE ps
    ;;

  *)
    error "Acción desconocida: '$ACTION'. Usa: up | down | restart | logs | status"
    ;;
esac
