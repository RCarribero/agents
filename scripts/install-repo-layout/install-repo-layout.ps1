param(
    [string]$TargetRoot = ".",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SourceFile {
    param(
        [string]$SourceRoot,
        [string]$CanonicalRelativePath,
        [string]$LegacyRelativePath
    )

    $candidates = @(
        (Join-Path $SourceRoot (Join-Path 'repo-templates/.github' $CanonicalRelativePath)),
        (Join-Path $SourceRoot (Join-Path '.github' $CanonicalRelativePath)),
        (Join-Path $SourceRoot $LegacyRelativePath)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Resolve-SourceDirectory {
    param(
        [string]$SourceRoot,
        [string]$CanonicalRelativePath,
        [string]$LegacyRelativePath
    )

    $candidates = @(
        (Join-Path $SourceRoot (Join-Path 'repo-templates/.github' $CanonicalRelativePath)),
        (Join-Path $SourceRoot (Join-Path '.github' $CanonicalRelativePath)),
        (Join-Path $SourceRoot $LegacyRelativePath)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Container) {
            return $candidate
        }
    }

    return $null
}

function Resolve-RootTemplate {
    param(
        [string]$SourceRoot,
        [string]$RelativePath
    )

    $candidates = @(
        (Join-Path $SourceRoot (Join-Path 'repo-templates' $RelativePath)),
        (Join-Path $SourceRoot $RelativePath)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Label,
        [bool]$Overwrite,
        [System.Collections.Generic.List[string]]$Created,
        [System.Collections.Generic.List[string]]$Updated,
        [System.Collections.Generic.List[string]]$Skipped
    )

    $parent = Split-Path $Target -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $exists = Test-Path $Target -PathType Leaf
    if ($exists -and -not $Overwrite) {
        $Skipped.Add($Label)
        return
    }

    Copy-Item -Path $Source -Destination $Target -Force

    if ($exists) {
        $Updated.Add($Label)
    }
    else {
        $Created.Add($Label)
    }
}

function Install-RelativeFile {
    param(
        [string]$SourceRoot,
        [string]$TargetRoot,
        [string]$RelativePath,
        [bool]$Overwrite,
        [System.Collections.Generic.List[string]]$Created,
        [System.Collections.Generic.List[string]]$Updated,
        [System.Collections.Generic.List[string]]$Skipped,
        [System.Collections.Generic.List[string]]$Missing
    )

    $source = Join-Path $SourceRoot $RelativePath
    if (Test-Path $source -PathType Leaf) {
        Copy-TemplateFile -Source $source -Target (Join-Path $TargetRoot $RelativePath) -Label $RelativePath -Overwrite $Overwrite -Created $Created -Updated $Updated -Skipped $Skipped
    }
    else {
        $Missing.Add($RelativePath)
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$resolvedTargetRoot = (Resolve-Path -Path $TargetRoot).Path

$created = [System.Collections.Generic.List[string]]::new()
$updated = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()

$copilotInstructionsSource = Resolve-SourceFile -SourceRoot $sourceRoot -CanonicalRelativePath 'copilot-instructions.md' -LegacyRelativePath 'copilot-instructions.md'
$promptsSource = Resolve-SourceDirectory -SourceRoot $sourceRoot -CanonicalRelativePath 'prompts' -LegacyRelativePath 'prompts'
$workflowsSource = Resolve-SourceDirectory -SourceRoot $sourceRoot -CanonicalRelativePath 'workflows' -LegacyRelativePath 'workflows'
$rootEnvTemplate = Resolve-RootTemplate -SourceRoot $sourceRoot -RelativePath '.env.example'

if ($copilotInstructionsSource) {
    Copy-TemplateFile -Source $copilotInstructionsSource -Target (Join-Path $resolvedTargetRoot '.github/copilot-instructions.md') -Label '.github/copilot-instructions.md' -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
}
else {
    $missing.Add('.github/copilot-instructions.md')
}

if ($promptsSource) {
    Get-ChildItem -Path $promptsSource -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $resolvedTargetRoot (Join-Path '.github/prompts' $_.Name)) -Label ".github/prompts/$($_.Name)" -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('.github/prompts/*')
}

if ($workflowsSource) {
    Get-ChildItem -Path $workflowsSource -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $resolvedTargetRoot (Join-Path '.github/workflows' $_.Name)) -Label ".github/workflows/$($_.Name)" -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('.github/workflows/*')
}

if ($rootEnvTemplate) {
    Copy-TemplateFile -Source $rootEnvTemplate -Target (Join-Path $resolvedTargetRoot '.env.example') -Label '.env.example' -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
}
else {
    $missing.Add('.env.example')
}

$relativeFiles = @(
    'scripts/invoke-git-bash.ps1',
    'scripts/install-repo-layout/install-repo-layout.sh',
    'scripts/install-repo-layout/install-repo-layout.ps1',
    'scripts/start/start.sh',
    'scripts/start/start.ps1',
    'scripts/verified_digest.py',
    'scripts/docker-launcher/setup.sh',
    'scripts/docker-launcher/setup.ps1',
    'scripts/docker-launcher/build.sh',
    'scripts/docker-launcher/build.ps1',
    'scripts/docker-launcher/launch.sh',
    'scripts/docker-launcher/launch.ps1'
)

foreach ($relativePath in $relativeFiles) {
    Install-RelativeFile -SourceRoot $sourceRoot -TargetRoot $resolvedTargetRoot -RelativePath $relativePath -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped -Missing $missing
}

Write-Output '=== install-repo-layout.ps1 ==='
Write-Output "Origen:  $sourceRoot"
Write-Output "Destino: $resolvedTargetRoot"
Write-Output ''

Write-Output 'Archivos creados:'
if ($created.Count -eq 0) {
    Write-Output '  - ninguno'
}
else {
    $created | ForEach-Object { Write-Output "  - $_" }
}

Write-Output ''
Write-Output 'Archivos actualizados:'
if ($updated.Count -eq 0) {
    Write-Output '  - ninguno'
}
else {
    $updated | ForEach-Object { Write-Output "  - $_" }
}

Write-Output ''
Write-Output 'Archivos omitidos:'
if ($skipped.Count -eq 0) {
    Write-Output '  - ninguno'
}
else {
    $skipped | ForEach-Object { Write-Output "  - $_" }
}

Write-Output ''
Write-Output 'Plantillas ausentes:'
if ($missing.Count -eq 0) {
    Write-Output '  - ninguna'
}
else {
    $missing | ForEach-Object { Write-Output "  - $_" }
}

Write-Output ''
Write-Output 'Siguiente paso: ejecuta /start o scripts/start.* dentro del repo destino para completar stack.md y los .env faltantes.'
