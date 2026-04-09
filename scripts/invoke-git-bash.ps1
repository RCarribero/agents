param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptPath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GitBashPath {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
        $gitBashFromGit = Join-Path $gitRoot 'bin\bash.exe'
        if (Test-Path $gitBashFromGit) {
            return $gitBashFromGit
        }
    }

    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $candidates += Join-Path $programFilesX86 'Git\bin\bash.exe'
    }

    if ($env:LocalAppData) {
        $candidates += Join-Path $env:LocalAppData 'Programs\Git\bin\bash.exe'
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw 'Git Bash no encontrado. Instala Git for Windows o ejecuta estos scripts desde Git Bash/WSL.'
}

$resolvedScriptPath = (Resolve-Path -Path $ScriptPath).Path
$gitBashPath = Get-GitBashPath

& $gitBashPath $resolvedScriptPath @ScriptArguments