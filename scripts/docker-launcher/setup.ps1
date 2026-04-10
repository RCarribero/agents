#Requires -Version 5.1
# docker-launcher/setup.ps1 — Comprueba prerequisitos y prepara el entorno para Docker.
#
# Uso: .\setup.ps1 [-EnvOnly]
#   -EnvOnly   Solo genera .env desde .env.example, sin verificar Docker.

param(
    [switch]$EnvOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Info    { param($msg) Write-Host "[setup] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[setup] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[setup][WARN] $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[setup][ERROR] $msg" -ForegroundColor Red; exit 1 }

# ── 1. Verificar prerequisitos ────────────────────────────────────────────────
if (-not $EnvOnly) {
    Write-Info "Verificando prerequisitos..."

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail "Docker no está instalado. Descárgalo desde https://docs.docker.com/get-docker/"
    }

    $dockerVersion = docker --version 2>&1
    Write-Success "Docker detectado: $dockerVersion"

    try {
        $null = docker info 2>&1
    } catch {
        Write-Fail "El demonio de Docker no está corriendo. Inicia Docker Desktop."
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "El demonio de Docker no está corriendo. Inicia Docker Desktop."
    }
    Write-Success "Demonio de Docker activo."

    # Preferir docker compose v2
    $useComposeV2 = $false
    try { $null = docker compose version 2>&1; $useComposeV2 = ($LASTEXITCODE -eq 0) } catch {}
    if ($useComposeV2) {
        $env:COMPOSE_CMD = "docker compose"
        Write-Success "Docker Compose v2 disponible."
    } elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        $env:COMPOSE_CMD = "docker-compose"
        Write-Warn "Usando docker-compose v1 (considera actualizar a Compose v2)."
    } else {
        Write-Fail "Docker Compose no encontrado. Instala Docker Desktop o el plugin 'docker compose'."
    }
}

# ── 2. Crear .env desde .env.example ─────────────────────────────────────────
Push-Location $ProjectRoot
try {

if ((Test-Path ".env.example") -and -not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Success ".env creado desde .env.example — edítalo con tus valores reales antes de continuar."
} elseif (-not (Test-Path ".env")) {
    Write-Warn "No existe .env ni .env.example. Crea un .env con las variables necesarias."
} else {
    Write-Info ".env ya existe, no se sobreescribe."
}

# ── 3. Verificar variables obligatorias ──────────────────────────────────────
if (Test-Path ".env") {
    $missingVars = @()
    $requiredVars = @("POSTGRES_PASSWORD")
    $envLines = Get-Content ".env" | Where-Object { $_ -match "^\s*[^#]" }

    foreach ($var in $requiredVars) {
        $line = $envLines | Where-Object { $_ -match "^${var}=" }
        if ($line) {
            $val = ($line -replace "^${var}=", "").Trim().Trim('"').Trim("'")
            if ([string]::IsNullOrWhiteSpace($val) -or $val -match "changeme|your-") {
                $missingVars += $var
            }
        } else {
            $missingVars += $var
        }
    }

    if ($missingVars.Count -gt 0) {
        Write-Warn "Las siguientes variables deben configurarse en .env antes de lanzar:"
        $missingVars | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
}

# ── 4. Crear red Docker si no existe ─────────────────────────────────────────
if (-not $EnvOnly -and (Get-Command docker -ErrorAction SilentlyContinue)) {
    $imageName = ""
    if (Test-Path "$ProjectRoot\.env") {
        $imageLine = Get-Content "$ProjectRoot\.env" | Where-Object { $_ -match "^IMAGE_NAME=" }
        if ($imageLine) { $imageName = ($imageLine -replace "^IMAGE_NAME=", "").Trim().Trim('"').Trim("'") }
    }
    if ([string]::IsNullOrWhiteSpace($imageName)) {
        $imageName = (Split-Path -Leaf $ProjectRoot).ToLower() -replace '\s', '-'
    }

    $networkName = "$imageName-net"
    $existingNet = docker network inspect $networkName 2>&1
    if ($LASTEXITCODE -ne 0) {
        docker network create $networkName | Out-Null
        Write-Info "Red Docker '$networkName' creada."
    } else {
        Write-Info "Red Docker '$networkName' ya existe."
    }
}

Write-Success "Setup completado. Siguiente paso: .\build.ps1"
} finally { Pop-Location }
