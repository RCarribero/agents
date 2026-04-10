param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Detect-UserPromptsDirectory {
    if ($env:VSCODE_USER_PROMPTS_FOLDER) {
        return $env:VSCODE_USER_PROMPTS_FOLDER
    }

    $candidates = @()

    if ($IsWindows) {
        if ($env:APPDATA) {
            $candidates += (Join-Path $env:APPDATA 'Code - Insiders\User\prompts')
            $candidates += (Join-Path $env:APPDATA 'Code\User\prompts')
        }
    }
    elseif ($IsMacOS) {
        $candidates += (Join-Path $HOME 'Library/Application Support/Code - Insiders/User/prompts')
        $candidates += (Join-Path $HOME 'Library/Application Support/Code/User/prompts')
    }
    else {
        $candidates += (Join-Path $HOME '.config/Code - Insiders/User/prompts')
        $candidates += (Join-Path $HOME '.config/Code/User/prompts')
    }

    foreach ($candidate in $candidates) {
        $parent = Split-Path $candidate -Parent
        if ((Test-Path $candidate) -or (Test-Path $parent)) {
            return $candidate
        }
    }

    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }

    throw 'No se pudo detectar la carpeta global de prompts. Define VSCODE_USER_PROMPTS_FOLDER.'
}

function Get-PromptInstallDirectories {
    param(
        [string]$PrimaryDirectory
    )

    $directories = [System.Collections.Generic.List[string]]::new()
    $directories.Add($PrimaryDirectory)

    if (-not $env:VSCODE_USER_PROMPTS_FOLDER) {
        $userRootDir = Split-Path $PrimaryDirectory -Parent
        $profilesDir = Join-Path $userRootDir 'profiles'

        if (Test-Path $profilesDir -PathType Container) {
            Get-ChildItem -Path $profilesDir -Directory | Sort-Object Name | ForEach-Object {
                $directories.Add((Join-Path $_.FullName 'prompts'))
            }
        }
    }

    return $directories | Select-Object -Unique
}

function Get-PromptScopeLabel {
    param(
        [string]$UserRootDir,
        [string]$PromptDirectory,
        [string]$PromptName
    )

    $defaultPromptDir = Join-Path $UserRootDir 'prompts'
    if ($PromptDirectory -eq $defaultPromptDir) {
        return "prompt:user:$PromptName"
    }

    $profilesRoot = Join-Path $UserRootDir 'profiles'
    if ($PromptDirectory.StartsWith($profilesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $profileId = Split-Path (Split-Path $PromptDirectory -Parent) -Leaf
        return "prompt:profile:${profileId}:$PromptName"
    }

    return "prompt:$PromptName"
}

function Get-BashFriendlyPath {
    param(
        [string]$Path
    )

    $normalized = $Path -replace '\\', '/'

    if ($IsWindows -and $normalized -match '^([A-Za-z]):/(.*)$') {
        return "/$($matches[1].ToLower())/$($matches[2])"
    }

    return $normalized
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

function Write-GlobalPrompt {
    param(
        [string]$TargetPath,
        [string]$Name,
        [string]$Label,
        [string]$Content,
        [bool]$Overwrite,
        [System.Collections.Generic.List[string]]$Created,
        [System.Collections.Generic.List[string]]$Updated,
        [System.Collections.Generic.List[string]]$Skipped
    )

    $parent = Split-Path $TargetPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $exists = Test-Path $TargetPath -PathType Leaf
    if ($exists -and -not $Overwrite) {
        $Skipped.Add($Label)
        return
    }

    Set-Content -Path $TargetPath -Value $Content -Encoding UTF8

    if ($exists) {
        $Updated.Add($Label)
    }
    else {
        $Created.Add($Label)
    }
}

function New-GlobalPromptContent {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Intro,
        [string[]]$WindowsCommands,
        [string[]]$BashCommands,
        [string[]]$ExpectedBehavior
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    $lines.Add("name: `"$Name`"")
    $lines.Add("description: `"$Description`"")
    $lines.Add('agent: "agent"')
    $lines.Add('---')
    $lines.Add('')
    $lines.Add($Intro)
    $lines.Add('')
    $lines.Add('Reglas de ejecución:')
    $lines.Add('')

    if ($WindowsCommands.Count -gt 0) {
        $lines.Add('- Si estás en Windows/PowerShell, usa estos comandos:')
        foreach ($command in $WindowsCommands) {
            $lines.Add("  - $command")
        }
    }

    if ($BashCommands.Count -gt 0) {
        $lines.Add('- Si estás en Bash, Git Bash o Linux/macOS, usa estos comandos:')
        foreach ($command in $BashCommands) {
            $lines.Add("  - $command")
        }
    }

    $lines.Add('')
    $lines.Add('Comportamiento esperado:')
    $lines.Add('')

    foreach ($line in $ExpectedBehavior) {
        $lines.Add("- $line")
    }

    return ($lines -join "`n")
}

function Invoke-McpJsonSync {
    param([string]$JsonPath)
    # Merges standard MCP servers into $JsonPath. Returns list of added key names.

    $targetServers = [ordered]@{
        "io.github.github/github-mcp-server" = [ordered]@{
            "type"    = "http"
            "url"     = "https://api.githubcopilot.com/mcp/"
            "gallery" = "https://api.mcp.github.com"
            "version" = "0.33.0"
        }
        "com.supabase/mcp" = [ordered]@{
            "type"    = "http"
            "url"     = "https://mcp.supabase.com/mcp"
            "gallery" = "https://api.mcp.github.com"
            "version" = "0.7.0"
        }
        "com.stripe/mcp" = [ordered]@{
            "type"    = "http"
            "url"     = "https://mcp.stripe.com"
            "gallery" = "https://api.mcp.github.com"
            "version" = "0.2.4"
        }
        "com.vercel/vercel-mcp" = [ordered]@{
            "type"    = "http"
            "url"     = "https://mcp.vercel.com"
            "gallery" = "https://api.mcp.github.com"
            "version" = "0.0.3"
        }
    }

    $servers = [ordered]@{}
    $inputs  = @()

    if (Test-Path $JsonPath -PathType Leaf) {
        $parsed = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($parsed.PSObject.Properties['servers'] -and $null -ne $parsed.servers) {
            $parsed.servers.PSObject.Properties | ForEach-Object {
                $servers[$_.Name] = $_.Value
            }
        }
        if ($parsed.PSObject.Properties['inputs'] -and $null -ne $parsed.inputs) {
            $inputs = $parsed.inputs
        }
    }

    $knownUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($kv in $servers.GetEnumerator()) {
        $v = $kv.Value
        if ($v -is [System.Management.Automation.PSCustomObject] -and $v.PSObject.Properties['url']) {
            [void]$knownUrls.Add($v.url)
        }
    }

    $added = [System.Collections.Generic.List[string]]::new()
    foreach ($kv in $targetServers.GetEnumerator()) {
        $key   = $kv.Key
        $entry = $kv.Value
        if ($servers.Contains($key)) { continue }
        if ($knownUrls.Contains($entry['url'])) { continue }
        $servers[$key] = $entry
        [void]$knownUrls.Add($entry['url'])
        $added.Add($key)
    }

    $parentDir = Split-Path $JsonPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir -PathType Container)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    [ordered]@{ servers = $servers; inputs = $inputs } |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $JsonPath -Encoding UTF8

    return ,$added
}

function Invoke-McpSyncLayout {
    param(
        [string]$UserRootDir,
        [System.Collections.Generic.List[string]]$Synced,
        [System.Collections.Generic.List[string]]$Unchanged,
        [System.Collections.Generic.List[string]]$Warned
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    $profilesDir = Join-Path $UserRootDir 'profiles'
    if (Test-Path $profilesDir -PathType Container) {
        Get-ChildItem -Path $profilesDir -Directory | Sort-Object Name | ForEach-Object {
            $targets.Add((Join-Path $_.FullName 'mcp.json'))
        }
    }
    $targets.Add((Join-Path $UserRootDir 'mcp.json'))

    foreach ($mcpFile in $targets) {
        try {
            $addedList = Invoke-McpJsonSync -JsonPath $mcpFile
            if ($addedList.Count -gt 0) {
                $Synced.Add("$mcpFile [+$($addedList -join ',')]")
            }
            else {
                $Unchanged.Add($mcpFile)
            }
        }
        catch {
            $Warned.Add("WARN ${mcpFile}: $_")
        }
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$userPromptsDir = Detect-UserPromptsDirectory
$promptInstallDirs = Get-PromptInstallDirectories -PrimaryDirectory $userPromptsDir
$userRootDir = Split-Path $userPromptsDir -Parent
$copilotToolsDir = if ($env:COPILOT_GLOBAL_TOOLS_DIR) { $env:COPILOT_GLOBAL_TOOLS_DIR } else { Join-Path $userRootDir 'copilot-tools' }
$toolsScriptsDir = Join-Path $copilotToolsDir 'scripts'
$toolsTemplatesDir = Join-Path $copilotToolsDir 'repo-templates'
$bashScriptsDir = Get-BashFriendlyPath -Path $toolsScriptsDir

$created = [System.Collections.Generic.List[string]]::new()
$updated = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
$mcpStatus    = 'SKIPPED'
$mcpDetails   = 'n/a'
$mcpSynced    = [System.Collections.Generic.List[string]]::new()
$mcpUnchanged = [System.Collections.Generic.List[string]]::new()
$mcpWarned    = [System.Collections.Generic.List[string]]::new()

foreach ($promptDir in $promptInstallDirs) {
    New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $toolsTemplatesDir '.github/prompts') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $toolsTemplatesDir '.github/workflows') -Force | Out-Null

$canonicalInstructions = Join-Path $sourceRoot '.github/copilot-instructions.md'
if (Test-Path $canonicalInstructions -PathType Leaf) {
    Copy-TemplateFile -Source $canonicalInstructions -Target (Join-Path $toolsTemplatesDir '.github/copilot-instructions.md') -Label 'toolkit:.github/copilot-instructions.md' -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
}
else {
    $missing.Add('toolkit:.github/copilot-instructions.md')
}

$sourcePromptsDir = Join-Path $sourceRoot '.github/prompts'
if (Test-Path $sourcePromptsDir -PathType Container) {
    Get-ChildItem -Path $sourcePromptsDir -Filter '*.prompt.md' -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $toolsTemplatesDir (Join-Path '.github/prompts' $_.Name)) -Label "toolkit:.github/prompts/$($_.Name)" -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('toolkit:.github/prompts/*')
}

$sourceWorkflowsDir = Join-Path $sourceRoot '.github/workflows'
if (Test-Path $sourceWorkflowsDir -PathType Container) {
    Get-ChildItem -Path $sourceWorkflowsDir -Filter '*.yml' -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $toolsTemplatesDir (Join-Path '.github/workflows' $_.Name)) -Label "toolkit:.github/workflows/$($_.Name)" -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('toolkit:.github/workflows/*')
}

$rootEnvTemplate = Join-Path $sourceRoot '.env.example'
if (Test-Path $rootEnvTemplate -PathType Leaf) {
    Copy-TemplateFile -Source $rootEnvTemplate -Target (Join-Path $toolsTemplatesDir '.env.example') -Label 'toolkit:.env.example' -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
}
else {
    $missing.Add('toolkit:.env.example')
}

$relativeFiles = @(
    'scripts/invoke-git-bash.ps1',
    'scripts/install-copilot-layout/install-copilot-layout.sh',
    'scripts/install-copilot-layout/install-copilot-layout.ps1',
    'scripts/install-repo-layout/install-repo-layout.sh',
    'scripts/install-repo-layout/install-repo-layout.ps1',
    'scripts/start/start.sh',
    'scripts/start/start.ps1',
    'scripts/validate-stack/validate-stack.sh',
    'scripts/validate-stack/validate-stack.ps1',
    'scripts/validate-agents/validate-agents.sh',
    'scripts/validate-agents/validate-agents.ps1',
    'scripts/validate-memory/validate-memory.sh',
    'scripts/validate-memory/validate-memory.ps1',
    'scripts/run-tests/run-tests.sh',
    'scripts/run-tests/run-tests.ps1',
    'scripts/run-lint/run-lint.sh',
    'scripts/run-lint/run-lint.ps1',
    'scripts/sandbox-run/sandbox-run.sh',
    'scripts/sandbox-run/sandbox-run.ps1',
    'scripts/Dockerfile.sandbox',
    'scripts/run_eval_gate.py',
    'scripts/token-report/token-report.sh',
    'scripts/token-report/token-report.ps1',
    'scripts/verified_digest.py'
)

foreach ($relativePath in $relativeFiles) {
    $source = Join-Path $sourceRoot $relativePath
    if (Test-Path $source -PathType Leaf) {
        $target = Join-Path $copilotToolsDir $relativePath
        Copy-TemplateFile -Source $source -Target $target -Label "toolkit:$relativePath" -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
    else {
        $missing.Add("toolkit:$relativePath")
    }
}

$globalPrompts = @(
    @{
        FileName = 'start.prompt.md'
        Name = 'start'
        Description = 'Bootstrap global mínimo del proyecto: crea copilot-instructions, detecta stack e intenta descargar skills'
        Intro = 'Inicializa el repositorio actual usando el toolkit global y resume el resultado.'
        WindowsCommands = @(
            ('& "{0}" .' -f (Join-Path $toolsScriptsDir 'start/start.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/start/start.sh" .' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo el bootstrap mínimo del proyecto actual.',
            'No sobrescribas archivos existentes.',
            'Crea .github/copilot-instructions.md si falta.',
            'Crea stack.md si falta.',
            'Intenta descargar skills con autoskills si está disponible, sin bloquear si falla.',
            'No copies .github/prompts, .github/workflows, scripts ni archivos .env* al repo destino.',
            'Resume qué archivos se crearon, cuáles ya existían y el estado de la descarga de skills.'
        )
    },
    @{
        FileName = 'validar.prompt.md'
        Name = 'validar'
        Description = 'Ejecuta las validaciones del workspace actual con el toolkit global'
        Intro = 'Valida el repositorio actual ejecutando las comprobaciones operativas estándar.'
        WindowsCommands = @(
            ('& "{0}" .' -f (Join-Path $toolsScriptsDir 'validate-stack/validate-stack.ps1')),
            ('& "{0}"' -f (Join-Path $toolsScriptsDir 'validate-agents/validate-agents.ps1')),
            ('& "{0}"' -f (Join-Path $toolsScriptsDir 'validate-memory/validate-memory.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/validate-stack/validate-stack.sh" .' -f $bashScriptsDir),
            ('bash "{0}/validate-agents/validate-agents.sh"' -f $bashScriptsDir),
            ('bash "{0}/validate-memory/validate-memory.sh"' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta las tres validaciones en orden.',
            'No modifiques archivos.',
            'Resume el resultado de cada script con exit code y hallazgos relevantes.'
        )
    },
    @{
        FileName = 'tests.prompt.md'
        Name = 'tests'
        Description = 'Ejecuta los tests del workspace actual con el toolkit global'
        Intro = 'Ejecuta los tests del repositorio actual y resume el resultado.'
        WindowsCommands = @(
            ('& "{0}" . --json' -f (Join-Path $toolsScriptsDir 'run-tests/run-tests.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/run-tests/run-tests.sh" . --json' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo el runner de tests.',
            'No modifiques archivos.',
            'Resume exit code, stack detectado y fallos relevantes si existen.'
        )
    },
    @{
        FileName = 'lint.prompt.md'
        Name = 'lint'
        Description = 'Ejecuta el lint del workspace actual con el toolkit global'
        Intro = 'Ejecuta el linter del repositorio actual y resume el resultado.'
        WindowsCommands = @(
            ('& "{0}" . --json' -f (Join-Path $toolsScriptsDir 'run-lint/run-lint.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/run-lint/run-lint.sh" . --json' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo el runner de lint.',
            'No modifiques archivos.',
            'Resume exit code, stack detectado y problemas relevantes si existen.'
        )
    },
    @{
        FileName = 'sandbox-tests.prompt.md'
        Name = 'sandbox-tests'
        Description = 'Ejecuta los tests del workspace actual en sandbox con el toolkit global'
        Intro = 'Ejecuta los tests del repositorio actual en sandbox y resume el resultado.'
        WindowsCommands = @(
            ('& "{0}" . tests --json' -f (Join-Path $toolsScriptsDir 'sandbox-run/sandbox-run.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/sandbox-run/sandbox-run.sh" . tests --json' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo tests en sandbox.',
            'No modifiques archivos.',
            'Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.',
            'Resume exit code y fallos relevantes si existen.'
        )
    },
    @{
        FileName = 'sandbox-lint.prompt.md'
        Name = 'sandbox-lint'
        Description = 'Ejecuta el lint del workspace actual en sandbox con el toolkit global'
        Intro = 'Ejecuta el linter del repositorio actual en sandbox y resume el resultado.'
        WindowsCommands = @(
            ('& "{0}" . lint --json' -f (Join-Path $toolsScriptsDir 'sandbox-run/sandbox-run.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/sandbox-run/sandbox-run.sh" . lint --json' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo lint en sandbox.',
            'No modifiques archivos.',
            'Indica si la ejecución fue en Docker o en host cuando sea visible en la salida.',
            'Resume exit code y problemas relevantes si existen.'
        )
    },
    @{
        FileName = 'eval-gate.prompt.md'
        Name = 'eval-gate'
        Description = 'Ejecuta el gate automático de contratos del workspace actual con el toolkit global'
        Intro = 'Ejecuta el gate automático de contratos y resume el resultado.'
        WindowsCommands = @(
            ('python "{0}" --root .' -f (Join-Path $toolsScriptsDir 'run_eval_gate.py'))
        )
        BashCommands = @(
            ('python "{0}/run_eval_gate.py" --root .' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo el eval gate.',
            'No modifiques archivos salvo el reporte generado por el propio script.',
            'Resume qué checks pasaron o fallaron y el exit code.'
        )
    }
)

foreach ($prompt in $globalPrompts) {
    $content = New-GlobalPromptContent -Name $prompt.Name -Description $prompt.Description -Intro $prompt.Intro -WindowsCommands $prompt.WindowsCommands -BashCommands $prompt.BashCommands -ExpectedBehavior $prompt.ExpectedBehavior
    foreach ($promptDir in $promptInstallDirs) {
        $label = Get-PromptScopeLabel -UserRootDir $userRootDir -PromptDirectory $promptDir -PromptName $prompt.Name
        Write-GlobalPrompt -TargetPath (Join-Path $promptDir $prompt.FileName) -Name $prompt.Name -Label $label -Content $content -Overwrite $Force.IsPresent -Created $created -Updated $updated -Skipped $skipped
    }
}

try {
    Invoke-McpSyncLayout -UserRootDir $userRootDir -Synced $mcpSynced -Unchanged $mcpUnchanged -Warned $mcpWarned
    if ($mcpSynced.Count -gt 0 -or $mcpUnchanged.Count -gt 0) {
        $mcpStatus  = 'OK'
        $mcpDetails = "sync completado ($($mcpSynced.Count) actualizado(s), $($mcpUnchanged.Count) sin cambios)"
    }
    elseif ($mcpWarned.Count -gt 0) {
        $mcpStatus  = 'WARN'
        $mcpDetails = $mcpWarned[0]
    }
}
catch {
    $mcpStatus  = 'WARN'
    $mcpDetails = "error en sync: $_"
}

Write-Output '=== install-copilot-layout.ps1 ==='
Write-Output "Origen:           $sourceRoot"
Write-Output "Prompts base:     $userPromptsDir"
if ($promptInstallDirs.Count -gt 1) {
    Write-Output 'Prompts de perfil:'
    $promptInstallDirs | Where-Object { $_ -ne $userPromptsDir } | ForEach-Object { Write-Output "  - $_" }
}
Write-Output "Toolkit global:   $copilotToolsDir"
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
Write-Output 'MCP sync:'
Write-Output "  - estado: $mcpStatus"
Write-Output "  - detalle: $mcpDetails"
if ($mcpSynced.Count -gt 0) {
    $mcpSynced | ForEach-Object { Write-Output "    updated: $_" }
}
if ($mcpWarned.Count -gt 0) {
    $mcpWarned | ForEach-Object { Write-Output "    $_" }
}

Write-Output ''
Write-Output 'Siguiente paso: recarga VS Code para ver /start, /validar, /tests, /lint y el resto de prompts globales.'