#Requires -Version 5.1
# docker-launcher/launch.ps1 — Lanza los contenedores Docker del proyecto.
#
# Uso: .\launch.ps1 [-Action <up|down|restart|logs|status>] [-NoDetach] [-Volumes] [-Service <nombre>]
#   up        Levanta los contenedores (default)
#   down      Para y elimina los contenedores (mantiene volúmenes)
#   restart   Reinicia los contenedores
#   logs      Muestra los logs en tiempo real
#   status    Muestra el estado de los contenedores
#   -NoDetach Corre en primer plano (útil para debug)
#   -Volumes  Junto con 'down', elimina también los volúmenes (¡destructivo!)
#   -Service  Aplica la acción solo a ese servicio

param(
    [ValidateSet("up","down","restart","logs","status")]
    [string]$Action  = "up",
    [switch]$NoDetach,
    [switch]$Volumes,
    [string]$Service = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Info    { param($msg) Write-Host "[launch] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[launch] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[launch][WARN] $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "[launch][ERROR] $msg" -ForegroundColor Red; exit 1 }

Set-Location $ProjectRoot

# ── Detectar Compose ──────────────────────────────────────────────────────────
$useV2 = $false
try { docker compose version 2>&1 | Out-Null; $useV2 = ($LASTEXITCODE -eq 0) } catch {}

$composeExe  = if ($useV2) { "docker" } else { "docker-compose" }
$composeBase = if ($useV2) { @("compose") } else { @() }

# ── Cargar .env ───────────────────────────────────────────────────────────────
if (Test-Path ".env") {
    Get-Content ".env" | Where-Object { $_ -match "^\s*[^#=\s]" -and $_ -match "=" } | ForEach-Object {
        $parts = $_ -split "=", 2
        $key   = $parts[0].Trim()
        $value = if ($parts.Length -gt 1) { $parts[1].Trim().Trim('"').Trim("'") } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

$imageName = $env:IMAGE_NAME
if ([string]::IsNullOrWhiteSpace($imageName)) {
    $imageName = (Split-Path -Leaf $ProjectRoot).ToLower() -replace '\s', '-'
}
$appPort = if ($env:APP_PORT) { $env:APP_PORT } else { "3000" }

# ── Ejecutar la acción ────────────────────────────────────────────────────────
switch ($Action) {

    "up" {
        Write-Info "Levantando contenedores$(if ($Service) { " (servicio: $Service)" })..."
        $args = $composeBase + @("up")
        if (-not $NoDetach) { $args += "--detach" }
        if ($Service)       { $args += $Service }

        & $composeExe @args
        if ($LASTEXITCODE -ne 0) { Write-Fail "Error al levantar contenedores." }

        if (-not $NoDetach) {
            Write-Success "Contenedores activos. App disponible en http://localhost:$appPort"
            Write-Info "  Ver logs:  .\launch.ps1 -Action logs"
            Write-Info "  Estado:    .\launch.ps1 -Action status"
            Write-Info "  Detener:   .\launch.ps1 -Action down"
        }
    }

    "down" {
        if ($Volumes) {
            Write-Warn "Se eliminarán los volúmenes de datos. Esta acción es IRREVERSIBLE."
            $confirm = Read-Host "¿Confirmar? [y/N]"
            if ($confirm -notmatch "^[Yy]$") { Write-Info "Cancelado."; exit 0 }
        }
        Write-Info "Deteniendo contenedores..."
        $args = $composeBase + @("down")
        if ($Volumes) { $args += "--volumes" }
        if ($Service) { $args += $Service }

        & $composeExe @args
        if ($LASTEXITCODE -ne 0) { Write-Fail "Error al detener contenedores." }
        Write-Success "Contenedores detenidos."
    }

    "restart" {
        Write-Info "Reiniciando contenedores$(if ($Service) { " (servicio: $Service)" })..."
        $args = $composeBase + @("restart")
        if ($Service) { $args += $Service }

        & $composeExe @args
        if ($LASTEXITCODE -ne 0) { Write-Fail "Error al reiniciar contenedores." }
        Write-Success "Contenedores reiniciados."
    }

    "logs" {
        Write-Info "Mostrando logs (Ctrl+C para salir)..."
        $args = $composeBase + @("logs", "--follow", "--tail=100")
        if ($Service) { $args += $Service }

        & $composeExe @args
    }

    "status" {
        $args = $composeBase + @("ps")
        & $composeExe @args
    }
}
