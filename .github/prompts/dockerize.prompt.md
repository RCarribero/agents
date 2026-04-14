---
name: "dockerize"
description: "Dockeriza el proyecto activo y genera un setup local completo: detecta el stack, instala prerequisitos, crea Dockerfile multi-stage, docker-compose, .dockerignore y la carpeta docker-launcher/ con scripts de setup/build/launch listos para usar"
agent: "agent"
---

Ejecuta los **dos objetivos** siguientes sobre el proyecto activo, en orden. No pidas confirmación entre pasos salvo que detectes un conflicto de sobreescritura en archivos existentes.

---

## PASO 0 — Detección de stack (base de ambos objetivos)

1. Lee `stack.md` en la raíz del proyecto. Si no existe, ejecuta:
  - PowerShell: `./scripts/start/start.ps1 .`
  - Bash/macOS/Linux: `bash ./scripts/start/start.sh .`
  Si tampoco puedes usar `/start`, detecta el stack manualmente inspeccionando manifests (`pubspec.yaml`, `package.json`, `pyproject.toml`, etc.) y continúa sin depender de scripts externos eliminados.
2. Identifica el **stack primario** (Flutter/Dart, Next.js, React, Python/FastAPI, Node.js genérico, etc.) y los **servicios auxiliares** (PostgreSQL, Redis…) según referencias en el código o en variables de entorno.
3. Lee `.env.example` si existe; si no, busca referencias a variables de entorno en el código y anótalas.

---

## OBJETIVO 1 — Setup local del entorno de desarrollo

### 1.1 Generar `.env`

- Si existe `.env.example` y **no** existe `.env`: copia `.env.example` a `.env`.
- Si no existe ninguno: crea `.env` con las variables mínimas detectadas para el stack (DATABASE_URL, PORT, SECRET_KEY, etc.) usando valores placeholder seguros. No uses contraseñas reales.
- Si ya existe `.env`: no lo sobreescribas; informa al usuario qué variables deben revisarse.

### 1.2 Instalar prerequisitos locales según el stack

Ejecuta los comandos correspondientes al stack detectado. Si alguno falla, registra el error pero **no abortes**; continúa con OBJETIVO 2.

**Node.js / Next.js / React:**
```bash
# Verifica runtime
node --version || echo "WARN: Node.js no encontrado — instálalo desde https://nodejs.org"
# Instala dependencias evitando npm por defecto
[ -f "pnpm-lock.yaml" ] && pnpm install --frozen-lockfile || \
  ([ -f "yarn.lock" ] && yarn install || pnpm install)
```

**Python / FastAPI / Django / Flask:**
```bash
# Linux/macOS
python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
# Windows PowerShell
python -m venv .venv; .venv\Scripts\Activate.ps1; pip install -r requirements.txt
```

**Flutter / Dart:**
```bash
flutter pub get
flutter doctor   # informa dependencias del sistema faltantes
```

**Genérico:** informa los archivos de dependencias encontrados y al usuario que instale manualmente.

---

## OBJETIVO 2 — Dockerización completa

### 2.1 Dockerfile multi-stage

Genera `Dockerfile` en la raíz. Reglas estrictas:

- **Nunca uses imágenes `latest`**; fija versiones exactas.
- Usa **multi-stage** siempre: al menos `deps/builder` + `runner`.
- Ordena instrucciones de mayor a menor frecuencia de cambio: dependencias antes que código fuente.
- Usa `--no-cache-dir` en pip y `--no-install-recommends` en apt.
- El proceso de la imagen final corre como usuario **no-root**.
- Añade `HEALTHCHECK` para servicios HTTP.
- Documenta brevemente cada stage con un comentario.
- En stacks Node.js / Next.js / React, preferir `pnpm` + `corepack`; evita `npm` salvo compatibilidad explícita exigida por el proyecto.

Plantillas por stack:

**Next.js / React:**
```dockerfile
# Stage 1: dependencias de producción
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

# Stage 2: build completo
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm build

# Stage 3: runtime mínimo
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1
CMD ["node_modules/.bin/next", "start"]
```

**Python / FastAPI:**
```dockerfile
# Stage 1: construir dependencias
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: runtime
FROM python:3.12-slim AS runner
WORKDIR /app
COPY --from=builder /install /usr/local
COPY . .
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser
EXPOSE 1453
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:145/health')" || exit 1
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "1453"]
```

**Flutter Web:**
```dockerfile
# Stage 1: compilar Flutter Web
FROM ghcr.io/cirruslabs/flutter:3.22.0 AS builder
WORKDIR /app
COPY pubspec.* ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

# Stage 2: servir con nginx
FROM nginx:1.27-alpine AS runner
COPY --from=builder /app/build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget -qO- http://localhost:80 || exit 1
```

**Node.js API genérico:**
```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile --prod

FROM node:20-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=deps /app/node_modules ./node_modules
COPY . .
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "src/index.js"]
```

---

### 2.2 `.dockerignore`

Crea `.dockerignore` en la raíz. Adapta según el stack:

```
.git
.gitignore
.env
.env.*
!.env.example
node_modules
.dart_tool
build/
dist/
.next/
out/
__pycache__
*.pyc
*.pyo
.pytest_cache
.venv
venv/
coverage/
*.log
*.md
!README.md
.DS_Store
Thumbs.db
docker-launcher/
.github/
```

---

### 2.3 `docker-compose.yml`

Genera `docker-compose.yml` en la raíz con estas reglas:

- Versión `"3.9"` o superior.
- Red interna entre servicios.
- `depends_on` con `condition: service_healthy` si hay base de datos.
- Volúmenes nombrados para datos persistentes; nunca bind-mounts de código en producción.
- Variables de entorno desde `env_file: .env`; **cero credenciales hardcodeadas** — usa `${VAR:?msg}` para las obligatorias.
- `restart: unless-stopped` en todos los servicios.
- Perfil `dev` con volumen de código y hot-reload si aplica al stack.

Incluye **solo** los servicios que el stack realmente necesite:

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner
    ports:
      - "${APP_PORT:-3000}:3000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped
    networks:
      - app-net

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?Variable POSTGRES_PASSWORD requerida en .env}
      POSTGRES_DB: ${POSTGRES_DB:-appdb}
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-app}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - app-net

volumes:
  db-data:

networks:
  app-net:
    driver: bridge
```

---

### 2.4 Carpeta `docker-launcher/` en la raíz del proyecto

Crea `docker-launcher/` con los 7 archivos siguientes. Sustituye `<APP_PORT>` por el puerto real.

---

#### `docker-launcher/setup.sh`

```bash
#!/usr/bin/env bash
# setup.sh — Verifica prerequisitos Docker y prepara .env.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[setup]${NC} $*"; }
success() { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[setup][WARN]${NC} $*"; }
error()   { echo -e "${RED}[setup][ERROR]${NC} $*" >&2; exit 1; }

command -v docker &>/dev/null || error "Docker no instalado. https://docs.docker.com/get-docker/"
docker info &>/dev/null       || error "Demonio de Docker no activo. Inicia Docker Desktop."
success "Docker $(docker --version) activo."
docker compose version &>/dev/null 2>&1 && COMPOSE="docker compose" \
  || { command -v docker-compose &>/dev/null && COMPOSE="docker-compose" \
       || error "Docker Compose no encontrado."; }
success "Compose: $COMPOSE"

cd "$ROOT"
if [ -f ".env.example" ] && [ ! -f ".env" ]; then
  cp .env.example .env
  success ".env creado desde .env.example — edita los valores antes de continuar."
elif [ ! -f ".env" ]; then
  warn "Sin .env ni .env.example. Crea .env con tus variables de entorno."
else
  info ".env ya existe."
fi
success "Setup listo. Siguiente: ./build.sh"
```

---

#### `docker-launcher/setup.ps1`

```powershell
#Requires -Version 5.1
# setup.ps1 — Verifica prerequisitos Docker y prepara .env.
param()
Set-StrictMode -Version Latest; $ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function info    { param($m) Write-Host "[setup] $m" -ForegroundColor Cyan }
function success { param($m) Write-Host "[setup] $m" -ForegroundColor Green }
function warn    { param($m) Write-Host "[setup][WARN] $m" -ForegroundColor Yellow }
function fail    { param($m) Write-Host "[setup][ERROR] $m" -ForegroundColor Red; exit 1 }

if (-not (Get-Command docker -EA SilentlyContinue)) { fail "Docker no instalado. https://docs.docker.com/get-docker/" }
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { fail "Demonio de Docker no activo. Inicia Docker Desktop." }
success "Docker $(docker --version) activo."
$v2 = $false; try { docker compose version 2>&1 | Out-Null; $v2 = ($LASTEXITCODE -eq 0) } catch {}
if (-not $v2 -and -not (Get-Command docker-compose -EA SilentlyContinue)) { fail "Docker Compose no encontrado." }
success "Compose disponible."

Set-Location $Root
if ((Test-Path ".env.example") -and -not (Test-Path ".env")) {
  Copy-Item .env.example .env
  success ".env creado — edita los valores antes de continuar."
} elseif (-not (Test-Path ".env")) {
  warn "Sin .env ni .env.example. Crea .env con tus variables."
} else { info ".env ya existe." }
success "Setup listo. Siguiente: .\build.ps1"
```

---

#### `docker-launcher/build.sh`

```bash
#!/usr/bin/env bash
# build.sh — Construye las imágenes Docker del proyecto.
# Uso: ./build.sh [--no-cache] [--service <nombre>]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NO_CACHE=""; SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in --no-cache) NO_CACHE="--no-cache"; shift ;; --service) SERVICE="$2"; shift 2 ;; *) echo "Arg desconocido: $1" >&2; exit 1 ;; esac
done
BLUE='\033[0;34m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[build]${NC} $*"; }
success() { echo -e "${GREEN}[build]${NC} $*"; }
error()   { echo -e "${RED}[build][ERROR]${NC} $*" >&2; exit 1; }

cd "$ROOT"
[ -f ".env" ] && { set -a; source .env; set +a; }
[ ! -f "docker-compose.yml" ] && error "docker-compose.yml no encontrado en $ROOT"
docker compose version &>/dev/null 2>&1 && COMPOSE="docker compose" || COMPOSE="docker-compose"

START=$(date +%s)
info "Construyendo imágenes${SERVICE:+ (servicio: $SERVICE)}..."
# shellcheck disable=SC2086
$COMPOSE build $NO_CACHE $SERVICE
success "Build completado en $(($(date +%s) - START))s. Siguiente: ./launch.sh"
```

---

#### `docker-launcher/build.ps1`

```powershell
#Requires -Version 5.1
# build.ps1 — Construye las imágenes Docker del proyecto.
param(
  [ValidateSet("build","rebuild")] [string]$Action = "build",
  [switch]$NoCache,
  [string]$Service = ""
)
Set-StrictMode -Version Latest; $ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function info    { param($m) Write-Host "[build] $m" -ForegroundColor Cyan }
function success { param($m) Write-Host "[build] $m" -ForegroundColor Green }
function warn    { param($m) Write-Host "[build][WARN] $m" -ForegroundColor Yellow }
function fail    { param($m) Write-Host "[build][ERROR] $m" -ForegroundColor Red; exit 1 }

if ($Action -eq "rebuild") { $NoCache = $true }
Set-Location $Root
if (Test-Path ".env") {
  Get-Content ".env" | Where-Object { $_ -match "^[^#=\s].*=" } | ForEach-Object {
    $p = $_ -split "=", 2
    [System.Environment]::SetEnvironmentVariable($p[0].Trim(), $p[1].Trim().Trim('"').Trim("'"), "Process")
  }
}
if (-not (Test-Path "docker-compose.yml")) { fail "docker-compose.yml no encontrado en $Root" }
$v2 = $false; try { docker compose version 2>&1 | Out-Null; $v2 = ($LASTEXITCODE -eq 0) } catch {}
$exe = if ($v2) { "docker" } else { "docker-compose" }
$base = if ($v2) { @("compose") } else { @() }

if ($Action -eq "rebuild") {
  $desc = if ($Service) { $Service } else { "todos los servicios" }
  warn "Rebuild: parando y eliminando imágenes de $desc..."
  $sa = $base + @("stop");  if ($Service) { $sa += $Service }; & $exe @sa 2>&1 | Out-Null
  $ra = $base + @("rm","-f"); if ($Service) { $ra += $Service }; & $exe @ra 2>&1 | Out-Null
  $ia = $base + @("images","-q"); if ($Service) { $ia += $Service }
  (& $exe @ia 2>&1) | Where-Object { $_ -match "^[0-9a-f]+$" } | ForEach-Object { docker rmi -f $_ 2>&1 | Out-Null }
  info "Imágenes eliminadas. Reconstruyendo..."
}

$args = $base + @("build")
if ($NoCache) { $args += "--no-cache" }
if ($Service) { $args += $Service }
$t = Get-Date; info "Construyendo imágenes$(if ($Service) { " (servicio: $Service)" })..."
& $exe @args
if ($LASTEXITCODE -ne 0) { fail "Build fallido." }
success "Build completado en $([math]::Round(((Get-Date) - $t).TotalSeconds))s. Siguiente: .\launch.ps1"
```

---

#### `docker-launcher/launch.sh`

```bash
#!/usr/bin/env bash
# launch.sh — Gestiona el ciclo de vida de los contenedores.
# Uso: ./launch.sh [up|down|restart|logs|status] [--no-detach] [--volumes] [--service <nombre>]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-up}"; shift || true
DETACH="--detach"; VOLUMES=""; SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-detach) DETACH=""; shift ;;
    --volumes)   VOLUMES="--volumes"; shift ;;
    --service)   SERVICE="$2"; shift 2 ;;
    *) echo "Arg desconocido: $1" >&2; exit 1 ;;
  esac
done
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[launch]${NC} $*"; }
success() { echo -e "${GREEN}[launch]${NC} $*"; }
warn()    { echo -e "${YELLOW}[launch][WARN]${NC} $*"; }
error()   { echo -e "${RED}[launch][ERROR]${NC} $*" >&2; exit 1; }

cd "$ROOT"
[ -f ".env" ] && { set -a; source .env; set +a; }
APP_PORT="${APP_PORT:-<APP_PORT>}"
docker compose version &>/dev/null 2>&1 && COMPOSE="docker compose" || COMPOSE="docker-compose"

case "$ACTION" in
  up)
    info "Levantando contenedores${SERVICE:+ (servicio: $SERVICE)}..."
    # shellcheck disable=SC2086
    $COMPOSE up $DETACH $SERVICE
    [ -n "$DETACH" ] && success "App en http://localhost:${APP_PORT} | Logs: ./launch.sh logs | Detener: ./launch.sh down"
    ;;
  down)
    [ -n "$VOLUMES" ] && { warn "Se eliminarán volúmenes. ¿Confirmar? [y/N]"; read -r C; [[ "$C" =~ ^[Yy]$ ]] || { info "Cancelado."; exit 0; }; }
    # shellcheck disable=SC2086
    $COMPOSE down $VOLUMES $SERVICE && success "Contenedores detenidos."
    ;;
  restart)
    # shellcheck disable=SC2086
    $COMPOSE restart $SERVICE && success "Contenedores reiniciados." ;;
  logs)
    # shellcheck disable=SC2086
    $COMPOSE logs --follow --tail=100 $SERVICE ;;
  status) $COMPOSE ps ;;
  *) error "Acción desconocida: '$ACTION'. Usa: up | down | restart | logs | status" ;;
esac
```

---

#### `docker-launcher/launch.ps1`

```powershell
#Requires -Version 5.1
# launch.ps1 — Gestiona el ciclo de vida de los contenedores.
param(
  [ValidateSet("up","down","restart","logs","status")] [string]$Action  = "up",
  [switch]$NoDetach,
  [switch]$Volumes,
  [string]$Service = ""
)
Set-StrictMode -Version Latest; $ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function info    { param($m) Write-Host "[launch] $m" -ForegroundColor Cyan }
function success { param($m) Write-Host "[launch] $m" -ForegroundColor Green }
function warn    { param($m) Write-Host "[launch][WARN] $m" -ForegroundColor Yellow }
function fail    { param($m) Write-Host "[launch][ERROR] $m" -ForegroundColor Red; exit 1 }

Set-Location $Root
if (Test-Path ".env") {
  Get-Content ".env" | Where-Object { $_ -match "^[^#=\s].*=" } | ForEach-Object {
    $p = $_ -split "=", 2
    [System.Environment]::SetEnvironmentVariable($p[0].Trim(), $p[1].Trim().Trim('"').Trim("'"), "Process")
  }
}
$appPort = if ($env:APP_PORT) { $env:APP_PORT } else { "<APP_PORT>" }
$v2 = $false; try { docker compose version 2>&1 | Out-Null; $v2 = ($LASTEXITCODE -eq 0) } catch {}
$exe = if ($v2) { "docker" } else { "docker-compose" }
$base = if ($v2) { @("compose") } else { @() }

switch ($Action) {
  "up" {
    $a = $base + @("up")
    if (-not $NoDetach) { $a += "--detach" }
    if ($Service) { $a += $Service }
    & $exe @a; if ($LASTEXITCODE -ne 0) { fail "Error al levantar contenedores." }
    if (-not $NoDetach) { success "App en http://localhost:$appPort | .\launch.ps1 -Action logs | .\launch.ps1 -Action down" }
  }
  "down" {
    if ($Volumes) { warn "Se eliminarán volúmenes. ¿Confirmar? [y/N]"; if ((Read-Host) -notmatch "^[Yy]$") { info "Cancelado."; exit 0 } }
    $a = $base + @("down"); if ($Volumes) { $a += "--volumes" }; if ($Service) { $a += $Service }
    & $exe @a; success "Contenedores detenidos."
  }
  "restart" {
    $a = $base + @("restart"); if ($Service) { $a += $Service }
    & $exe @a; success "Contenedores reiniciados."
  }
  "logs" {
    $a = $base + @("logs", "--follow", "--tail=100"); if ($Service) { $a += $Service }
    & $exe @a
  }
  "status" { & $exe @($base + @("ps")) }
}
```

---

#### `docker-launcher/README.md`

```markdown
# docker-launcher

Scripts para construir y gestionar los contenedores Docker del proyecto.

## Requisitos
- Docker >= 24 con Compose v2 (o docker-compose v1 como fallback)

## Inicio rápido

### Linux / macOS / Git Bash
```bash
cd docker-launcher && chmod +x *.sh
./setup.sh    # verifica Docker y crea .env
./build.sh    # construye las imágenes
./launch.sh   # levanta los contenedores
```

### Windows PowerShell
```powershell
cd docker-launcher
.\setup.ps1; .\build.ps1; .\launch.ps1
```

## Acciones de launch

| Acción   | Bash                         | PowerShell                          |
|----------|------------------------------|-------------------------------------|
| Levantar | `./launch.sh up`             | `.\launch.ps1 -Action up`           |
| Detener  | `./launch.sh down`           | `.\launch.ps1 -Action down`         |
| Reiniciar| `./launch.sh restart`        | `.\launch.ps1 -Action restart`      |
| Logs     | `./launch.sh logs`           | `.\launch.ps1 -Action logs`         |
| Estado   | `./launch.sh status`         | `.\launch.ps1 -Action status`       |

Flags extra: `--no-cache` en `build`, `--volumes` en `down` (destructivo), `--service <nombre>` para un servicio concreto.
```

---

## Validación final

Tras crear todos los archivos, verifica:

1. El `Dockerfile` tiene al menos 2 stages y el proceso final **no corre como root**.
2. `.dockerignore` excluye `.env`, dependencias pesadas (node_modules / .dart_tool / __pycache__) y `.git`.
3. `docker-compose.yml` no tiene credenciales hardcodeadas.
4. Todos los scripts de `docker-launcher/` existen. En entornos bash, aplica permisos: `chmod +x docker-launcher/*.sh`.

---

## Salida esperada

Responde con:
- Stack detectado y decisiones tomadas.
- Qué se instaló localmente (OBJETIVO 1) y si hubo errores.
- Lista de archivos Docker creados / ya existentes (sin sobreescribir preexistentes).
- Comandos de inicio rápido:
  ```bash
  # Linux / macOS / Git Bash
  cd docker-launcher && ./setup.sh && ./build.sh && ./launch.sh

  # Windows PowerShell
  cd docker-launcher; .\setup.ps1; .\build.ps1; .\launch.ps1
  ```
- Advertencias sobre variables de `.env` que el usuario debe completar antes de lanzar.
