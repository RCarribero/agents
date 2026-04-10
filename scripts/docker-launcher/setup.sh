#!/usr/bin/env bash
# docker-launcher/setup.sh — Comprueba prerequisitos y prepara el entorno para Docker.
#
# Uso: ./setup.sh [--env-only]
#   --env-only   Solo genera .env desde .env.example, sin verificar Docker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_ONLY="${1:-}"

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[setup]${NC} $*"; }
success() { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[setup][WARN]${NC} $*"; }
error()   { echo -e "${RED}[setup][ERROR]${NC} $*" >&2; exit 1; }

# ── 1. Verificar prerequisitos ────────────────────────────────────────────────
if [ "$ENV_ONLY" != "--env-only" ]; then
  info "Verificando prerequisitos..."

  if ! command -v docker &>/dev/null; then
    error "Docker no está instalado. Instálalo desde https://docs.docker.com/get-docker/"
  fi

  DOCKER_VERSION=$(docker --version 2>&1)
  success "Docker detectado: $DOCKER_VERSION"

  # Verificar que el demonio esté corriendo
  if ! docker info &>/dev/null; then
    error "El demonio de Docker no está corriendo. Inicia Docker Desktop o el servicio 'docker'."
  fi
  success "Demonio de Docker activo."

  # Preferir docker compose v2, fallback a docker-compose v1
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    success "Docker Compose v2 disponible."
  elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    warn "Usando docker-compose v1 (considera actualizar a Compose v2)."
  else
    error "Docker Compose no encontrado. Instala Docker Desktop o 'docker compose' plugin."
  fi

  export COMPOSE_CMD
fi

# ── 2. Crear .env desde .env.example ─────────────────────────────────────────
cd "$PROJECT_ROOT"

if [ -f ".env.example" ] && [ ! -f ".env" ]; then
  cp ".env.example" ".env"
  success ".env creado desde .env.example — edítalo con tus valores reales antes de continuar."
elif [ ! -f ".env" ]; then
  warn "No existe .env ni .env.example. Crea un .env con las variables necesarias."
elif [ -f ".env" ]; then
  info ".env ya existe, no se sobreescribe."
fi

# ── 3. Verificar variables obligatorias ──────────────────────────────────────
if [ -f ".env" ]; then
  MISSING_VARS=()
  # Variables que no deben quedar vacías ni con valor placeholder
  REQUIRED_VARS=("POSTGRES_PASSWORD")
  for VAR in "${REQUIRED_VARS[@]}"; do
    VAL=$(grep -E "^${VAR}=" ".env" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'")
    if [ -z "$VAL" ] || [[ "$VAL" == *"changeme"* ]] || [[ "$VAL" == *"your-"* ]]; then
      MISSING_VARS+=("$VAR")
    fi
  done

  if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    warn "Las siguientes variables deben configurarse en .env antes de lanzar:"
    for V in "${MISSING_VARS[@]}"; do echo "  - $V"; done
  fi
fi

# ── 4. Crear volúmenes y red si no existen ────────────────────────────────────
if [ "$ENV_ONLY" != "--env-only" ] && command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  # Leer IMAGE_NAME del .env si está definido, o usar nombre del directorio del proyecto
  IMAGE_NAME=$(grep -E "^IMAGE_NAME=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
  if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
  fi

  # Crear red si no existe
  NETWORK_NAME="${IMAGE_NAME}-net"
  if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    docker network create "$NETWORK_NAME" &>/dev/null || true
    info "Red Docker '${NETWORK_NAME}' creada."
  else
    info "Red Docker '${NETWORK_NAME}' ya existe."
  fi
fi

success "Setup completado. Siguiente paso: ./build.sh"
