#Requires -Version 5.1
# docker-launcher/build.ps1 — Construye las imágenes Docker del proyecto.
#
# Uso: .\build.ps1 [-Action <build|rebuild>] [-NoCache] [-Target <stage>] [-Service <nombre>]
#   build (default)   Construye las imágenes (usa caché si existe)
#   rebuild           Para contenedores, elimina imágenes y reconstruye desde cero
#   -NoCache          Fuerza rebuild sin caché de capas
#   -Target <stage>   Construye solo hasta ese stage del Dockerfile
#   -Service <nombre> Aplica la acción solo a ese servicio de docker-compose

param(
    [ValidateSet("build", "rebuild")]
    [string]$Action  = "build",
    [switch]$NoCache,
    [string]$Target  = "",
    [string]$Service = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Info    { param($msg) Write-Host "[build] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[build] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[build][WARN] $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[build][ERROR] $msg" -ForegroundColor Red; exit 1 }

Set-Location $ProjectRoot

# ── 1. Verificar archivos clave ───────────────────────────────────────────────
if (-not (Test-Path "Dockerfile") -and -not (Test-Path "docker-compose.yml")) {
    Write-Fail "No se encontró Dockerfile ni docker-compose.yml en $ProjectRoot"
}

# ── 2. Cargar .env ────────────────────────────────────────────────────────────
if (Test-Path ".env") {
    Get-Content ".env" | Where-Object { $_ -match "^\s*[^#=\s]" -and $_ -match "=" } | ForEach-Object {
        $parts = $_ -split "=", 2
        $key   = $parts[0].Trim()
        $value = if ($parts.Length -gt 1) { $parts[1].Trim().Trim('"').Trim("'") } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
    Write-Info ".env cargado."
} else {
    Write-Warn "No se encontró .env. Ejecuta .\setup.ps1 primero si es necesario."
}

# ── 3. Detectar nombre de imagen ──────────────────────────────────────────────
$imageName = $env:IMAGE_NAME
if ([string]::IsNullOrWhiteSpace($imageName)) {
    $imageName = (Split-Path -Leaf $ProjectRoot).ToLower() -replace '\s', '-'
}
$imageTag  = if ($env:IMAGE_TAG) { $env:IMAGE_TAG } else { "latest" }
$fullImage = "${imageName}:${imageTag}"

# ── 4. Seleccionar modo de build ────────────────────────────────────────────
# rebuild implica siempre --no-cache
if ($Action -eq "rebuild") { $NoCache = $true }

$startTime = Get-Date

if (Test-Path "docker-compose.yml") {
    # Detectar Compose v2 vs v1
    $useV2 = $false
    try { docker compose version 2>&1 | Out-Null; $useV2 = ($LASTEXITCODE -eq 0) } catch {}
    $composeCmd  = if ($useV2) { "docker" } else { "docker-compose" }
    $composeBase = if ($useV2) { @("compose") } else { @() }

    # ── Rebuild: parar contenedores y borrar imágenes ────────────────────────────
    if ($Action -eq "rebuild") {
        $targetDesc = if ($Service) { $Service } else { "todos los servicios" }
        Write-Warn "Rebuild: parando y eliminando imágenes de $targetDesc..."
        $stopArgs = $composeBase + @("stop")
        if ($Service) { $stopArgs += $Service }
        & $composeCmd @stopArgs 2>&1 | Out-Null

        $rmArgs = $composeBase + @("rm", "-f")
        if ($Service) { $rmArgs += $Service }
        & $composeCmd @rmArgs 2>&1 | Out-Null

        # Eliminar imágenes locales
        $imgArgs = $composeBase + @("images", "-q")
        if ($Service) { $imgArgs += $Service }
        $imgs = (& $composeCmd @imgArgs 2>&1) | Where-Object { $_ -match "^[0-9a-f]+$" }
        if ($imgs) {
            $imgs | ForEach-Object { docker rmi -f $_ 2>&1 | Out-Null }
            Write-Info "Imágenes anteriores eliminadas."
        }
        Write-Info "Comenzando rebuild sin caché..."
    }

    $composeArgs = $composeBase + @("build")
    if ($NoCache) { $composeArgs += "--no-cache" }
    if ($Service) { $composeArgs += $Service }

    Write-Info "Construyendo con Compose..."
    & $composeCmd @composeArgs
    if ($LASTEXITCODE -ne 0) { Write-Fail "Build fallido (exit code $LASTEXITCODE)." }

} else {
    # Build directo con docker build
    if ($Action -eq "rebuild") {
        Write-Warn "Rebuild: eliminando imagen $fullImage..."
        docker rmi -f $fullImage 2>&1 | Out-Null
        Write-Info "Imagen eliminada. Comenzando rebuild sin caché..."
    }

    $buildArgs = @("build", "-t", $fullImage)
    if ($NoCache) { $buildArgs += "--no-cache" }
    if ($Target)  { $buildArgs += "--target"; $buildArgs += $Target }
    $buildArgs += "."

    Write-Info "Construyendo imagen $fullImage ..."
    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) { Write-Fail "Build fallido (exit code $LASTEXITCODE)." }
}

$elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
Write-Success "Build completado en ${elapsed}s. Siguiente paso: .\launch.ps1"
