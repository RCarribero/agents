param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PS 5.1 compat: $IsWindows/$IsMacOS/$IsLinux only exist in PS 6+
if (-not (Test-Path variable:IsWindows)) {
    $IsWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    $IsMacOS   = [System.Environment]::OSVersion.Platform -eq 'Unix' -and
                 (uname -s 2>$null) -eq 'Darwin'
    $IsLinux   = [System.Environment]::OSVersion.Platform -eq 'Unix' -and
                 -not $IsMacOS
}

$overwriteExisting = $true

function Detect-UserPromptsDirectory {
    if ($env:VSCODE_USER_PROMPTS_FOLDER) {
        return $env:VSCODE_USER_PROMPTS_FOLDER
    }

    $candidates = @()

    if ($IsWindows) {
        if ($env:APPDATA) {
            $candidates += (Join-Path $env:APPDATA 'Agents - Insiders\User\prompts')
            $candidates += (Join-Path $env:APPDATA 'Agents\User\prompts')
            $candidates += (Join-Path $env:APPDATA 'Code - Insiders\User\prompts')
            $candidates += (Join-Path $env:APPDATA 'Code\User\prompts')
        }
    }
    elseif ($IsMacOS) {
        $candidates += (Join-Path $HOME 'Library/Application Support/Agents - Insiders/User/prompts')
        $candidates += (Join-Path $HOME 'Library/Application Support/Agents/User/prompts')
        $candidates += (Join-Path $HOME 'Library/Application Support/Code - Insiders/User/prompts')
        $candidates += (Join-Path $HOME 'Library/Application Support/Code/User/prompts')
    }
    else {
        $candidates += (Join-Path $HOME '.config/Agents - Insiders/User/prompts')
        $candidates += (Join-Path $HOME '.config/Agents/User/prompts')
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

    return @($directories | Select-Object -Unique)
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

function Get-GlobalHookEntries {
    param([string]$HookScriptsDir)

    # mapping: EventName -> list of @{ name; script_basename; timeout }
    return [ordered]@{
        SessionStart     = @(@{ name = 'session-start'; timeout = 15 })
        UserPromptSubmit = @(@{ name = 'user-prompt';   timeout = 10 })
        PreToolUse       = @(@{ name = 'pre-tool';      timeout = 10 })
        PostToolUse      = @(@{ name = 'post-tool';     timeout = 15 })
        SubagentStop     = @(@{ name = 'subagent-stop'; timeout = 10 })
        Stop             = @(@{ name = 'agent-stop';    timeout = 10 })
        SessionEnd       = @(@{ name = 'session-end';   timeout = 15 })
        Error            = @(@{ name = 'error-occurred'; timeout = 10 })
    }
}

function New-GlobalHookEntry {
    param(
        [string]$HookScriptsDir,
        [string]$Name,
        [int]$Timeout
    )

    $ps1 = Join-Path $HookScriptsDir ("$Name.ps1")
    $sh  = Join-Path $HookScriptsDir ("$Name.sh")
    $shUnix = Get-BashFriendlyPath -Path $sh

    $winCmd   = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ps1`""
    $unixCmd  = "bash `"$shUnix`""

    return [ordered]@{
        type    = 'command'
        command = $winCmd
        windows = $winCmd
        linux   = $unixCmd
        osx     = $unixCmd
        timeout = $Timeout
        env     = [ordered]@{
            COPILOT_ORCHESTRA_GLOBAL_HOOK = '1'
            COPILOT_ORCHESTRA_HOOK_NAME   = $Name
        }
    }
}

function Get-PythonExe {
    foreach ($candidate in @('python','python3','py')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Sync-GlobalHooks {
    param(
        [string]$HookScriptsDir,
        [ref]$StatusRef,
        [ref]$DetailsRef,
        [ref]$PathRef
    )

    $hooksDir = Join-Path $HOME '.copilot/hooks'
    $orchestraPath = Join-Path $hooksDir 'orchestra.json'
    $PathRef.Value = $orchestraPath

    if (-not (Test-Path $hooksDir -PathType Container)) {
        New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
    }

    $py = Get-PythonExe
    if (-not $py) {
        $StatusRef.Value  = 'SKIPPED'
        $DetailsRef.Value = 'python no disponible (necesario para merge JSON seguro)'
        return
    }

    $entries = Get-GlobalHookEntries -HookScriptsDir $HookScriptsDir
    $managed = [ordered]@{}
    foreach ($evt in $entries.Keys) {
        $list = @()
        foreach ($spec in $entries[$evt]) {
            $list += ,(New-GlobalHookEntry -HookScriptsDir $HookScriptsDir -Name $spec.name -Timeout $spec.timeout)
        }
        $managed[$evt] = $list
    }
    $managedJson = $managed | ConvertTo-Json -Depth 10 -Compress

    $pyScript = @'
import sys, json, os
target = sys.argv[1]
managed = json.loads(sys.argv[2])

data = {}
if os.path.isfile(target):
    try:
        with open(target, encoding="utf-8-sig") as f:
            data = json.load(f)
    except Exception as e:
        print("PARSE_ERROR:" + str(e))
        sys.exit(2)

if not isinstance(data, dict):
    print("PARSE_ERROR:root not object")
    sys.exit(2)

if not isinstance(data.get("hooks"), dict):
    data["hooks"] = {}

added, replaced = 0, 0
for event, mlist in managed.items():
    existing = data["hooks"].get(event)
    if not isinstance(existing, list):
        existing = []
    kept = []
    for item in existing:
        env = item.get("env") if isinstance(item, dict) else None
        if isinstance(env, dict) and str(env.get("COPILOT_ORCHESTRA_GLOBAL_HOOK","")) == "1":
            replaced += 1
            continue
        kept.append(item)
    kept.extend(mlist)
    added += len(mlist)
    data["hooks"][event] = kept

os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("OK:added=%d;replaced=%d" % (added, replaced))
'@

    $tmp = New-TemporaryFile
    try {
        Set-Content -Path $tmp -Value $pyScript -Encoding UTF8
        $out = & $py $tmp.FullName $orchestraPath $managedJson 2>&1
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            $StatusRef.Value  = 'WARN'
            $DetailsRef.Value = "no se pudo escribir orchestra.json (exit=$exit): $out"
            return
        }
        $StatusRef.Value  = 'OK'
        $DetailsRef.Value = "$out"
    }
    finally {
        Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Update-VSCodeHookSettings {
    param(
        [string]$UserRootDir,
        [ref]$StatusRef,
        [ref]$DetailsRef,
        [ref]$PathRef
    )

    $settingsPath = Join-Path $UserRootDir 'settings.json'
    $PathRef.Value = $settingsPath

    $py = Get-PythonExe
    if (-not $py) {
        $StatusRef.Value  = 'SKIPPED'
        $DetailsRef.Value = 'python no disponible'
        return
    }

    $pyScript = @'
import sys, json, os
target = sys.argv[1]
hook_loc = "~/.copilot/hooks"

data = {}
if os.path.isfile(target):
    try:
        with open(target, encoding="utf-8-sig") as f:
            data = json.load(f)
    except Exception as e:
        print("PARSE_ERROR:" + str(e))
        sys.exit(2)

if not isinstance(data, dict):
    print("PARSE_ERROR:root not object")
    sys.exit(2)

locs = data.get("chat.hookFilesLocations")
if not isinstance(locs, dict):
    locs = {}
prev = locs.get(hook_loc)
locs[hook_loc] = True
data["chat.hookFilesLocations"] = locs

os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")

if prev is True:
    print("OK:unchanged")
else:
    print("OK:registered=%s" % hook_loc)
'@

    $tmp = New-TemporaryFile
    try {
        Set-Content -Path $tmp -Value $pyScript -Encoding UTF8
        $out = & $py $tmp.FullName $settingsPath 2>&1
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            $StatusRef.Value  = 'WARN'
            $DetailsRef.Value = "settings.json no actualizado (exit=$exit): $out"
            return
        }
        $StatusRef.Value  = 'OK'
        $DetailsRef.Value = "$out"
    }
    finally {
        Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Clear-LegacyClaudeManagedHooks {
    param(
        [ref]$StatusRef,
        [ref]$DetailsRef,
        [ref]$PathRef
    )

    $legacyPath = Join-Path $HOME '.claude/settings.json'
    $PathRef.Value = $legacyPath

    if (-not (Test-Path $legacyPath -PathType Leaf)) {
        $StatusRef.Value  = 'SKIPPED'
        $DetailsRef.Value = 'no existe ~/.claude/settings.json'
        return
    }

    $py = Get-PythonExe
    if (-not $py) {
        $StatusRef.Value  = 'SKIPPED'
        $DetailsRef.Value = 'python no disponible'
        return
    }

    $pyScript = @'
import sys, json, os
target = sys.argv[1]

if not os.path.isfile(target):
    print("OK:absent")
    sys.exit(0)

try:
    with open(target, encoding="utf-8-sig") as f:
        data = json.load(f)
except Exception as e:
    print("PARSE_ERROR:" + str(e))
    sys.exit(2)

if not isinstance(data, dict):
    print("PARSE_ERROR:root not object")
    sys.exit(2)

removed = 0
hooks = data.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks.keys()):
        items = hooks.get(event)
        if not isinstance(items, list):
            continue
        kept = []
        for item in items:
            env = item.get("env") if isinstance(item, dict) else None
            if isinstance(env, dict) and str(env.get("COPILOT_ORCHESTRA_GLOBAL_HOOK","")) == "1":
                removed += 1
                continue
            kept.append(item)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        del data["hooks"]

if removed == 0:
    print("OK:removed=0")
    sys.exit(0)

with open(target, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("OK:removed=%d" % removed)
'@

    $tmp = New-TemporaryFile
    try {
        Set-Content -Path $tmp -Value $pyScript -Encoding UTF8
        $out = & $py $tmp.FullName $legacyPath 2>&1
        $exit = $LASTEXITCODE
        if ($exit -ne 0) {
            $StatusRef.Value  = 'WARN'
            $DetailsRef.Value = "no se pudo limpiar settings.json legacy (exit=$exit): $out"
            return
        }
        $StatusRef.Value  = 'OK'
        $DetailsRef.Value = "$out"
    }
    finally {
        Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$userPromptsDir = Detect-UserPromptsDirectory
$promptInstallDirs = @(Get-PromptInstallDirectories -PrimaryDirectory $userPromptsDir)
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
$globalHooksStatus  = 'SKIPPED'
$globalHooksDetails = 'n/a'
$globalHooksPath    = ''
$vscodeSettingsStatus  = 'SKIPPED'
$vscodeSettingsDetails = 'n/a'
$vscodeSettingsPath    = ''
$legacyClaudeStatus    = 'SKIPPED'
$legacyClaudeDetails   = 'n/a'
$legacyClaudePath      = ''

foreach ($promptDir in $promptInstallDirs) {
    New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $toolsTemplatesDir '.github/prompts') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $toolsTemplatesDir '.github/workflows') -Force | Out-Null

$legacyWorkspaceHooksTemplateDir = Join-Path $toolsTemplatesDir '.github/hooks'
if (Test-Path $legacyWorkspaceHooksTemplateDir -PathType Container) {
    Remove-Item -Path $legacyWorkspaceHooksTemplateDir -Recurse -Force
}

$canonicalInstructions = Join-Path $sourceRoot '.github/copilot-instructions.md'
if (Test-Path $canonicalInstructions -PathType Leaf) {
    Copy-TemplateFile -Source $canonicalInstructions -Target (Join-Path $toolsTemplatesDir '.github/copilot-instructions.md') -Label 'toolkit:.github/copilot-instructions.md' -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
}
else {
    $missing.Add('toolkit:.github/copilot-instructions.md')
}

$sourcePromptsDir = Join-Path $sourceRoot '.github/prompts'
if (Test-Path $sourcePromptsDir -PathType Container) {
    Get-ChildItem -Path $sourcePromptsDir -Filter '*.prompt.md' -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $toolsTemplatesDir (Join-Path '.github/prompts' $_.Name)) -Label "toolkit:.github/prompts/$($_.Name)" -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('toolkit:.github/prompts/*')
}

$sourceWorkflowsDir = Join-Path $sourceRoot '.github/workflows'
if (Test-Path $sourceWorkflowsDir -PathType Container) {
    Get-ChildItem -Path $sourceWorkflowsDir -Filter '*.yml' -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $toolsTemplatesDir (Join-Path '.github/workflows' $_.Name)) -Label "toolkit:.github/workflows/$($_.Name)" -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('toolkit:.github/workflows/*')
}

$rootEnvTemplate = Join-Path $sourceRoot '.env.example'
if (Test-Path $rootEnvTemplate -PathType Leaf) {
    Copy-TemplateFile -Source $rootEnvTemplate -Target (Join-Path $toolsTemplatesDir '.env.example') -Label 'toolkit:.env.example' -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
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
    'scripts/verified_digest.py'
)

foreach ($relativePath in $relativeFiles) {
    $source = Join-Path $sourceRoot $relativePath
    if (Test-Path $source -PathType Leaf) {
        $target = Join-Path $copilotToolsDir $relativePath
        Copy-TemplateFile -Source $source -Target $target -Label "toolkit:$relativePath" -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
    }
    else {
        $missing.Add("toolkit:$relativePath")
    }
}

$sourceHookScriptsDir = Join-Path $sourceRoot 'scripts/hooks'
if (Test-Path $sourceHookScriptsDir -PathType Container) {
    Get-ChildItem -Path $sourceHookScriptsDir -File | Sort-Object Name | ForEach-Object {
        Copy-TemplateFile -Source $_.FullName -Target (Join-Path $copilotToolsDir (Join-Path 'scripts/hooks' $_.Name)) -Label "toolkit:scripts/hooks/$($_.Name)" -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
    }
}
else {
    $missing.Add('toolkit:scripts/hooks/*')
}

$globalPrompts = @(
    @{
        FileName = 'start.prompt.md'
        Name = 'start'
        Description = 'Bootstrap minimo del proyecto (copilot-instructions, stack.md). Hooks son SOLO globales via install-copilot-layout; /start NO crea hooks workspace.'
        Intro = 'Inicializa el repositorio actual usando el toolkit global y resume el resultado. IMPORTANTE: Los hooks de orquestacion son SOLO GLOBALES (~/.copilot/hooks/orchestra.json) e instalados por install-copilot-layout. /start NO crea ni copia hooks workspace (.github/hooks/, scripts/hooks/).'
        WindowsCommands = @(
            ('& "{0}" .' -f (Join-Path $toolsScriptsDir 'start/start.ps1'))
        )
        BashCommands = @(
            ('bash "{0}/start/start.sh" .' -f $bashScriptsDir)
        )
        ExpectedBehavior = @(
            'Ejecuta solo el bootstrap minimo del proyecto actual.',
            'No sobrescribe archivos existentes; solo crea los que falten.',
            'Crea .github/copilot-instructions.md si falta.',
            'Crea stack.md si falta.',
            'Intenta descargar skills con autoskills si esta disponible, sin bloquear si falla.',
            'NO crea .github/hooks/, scripts/hooks/, .github/prompts, .github/workflows, ni archivos .env* en el repo destino.',
            'Resume que archivos se crearon o ya existian y el estado de la descarga de skills.'
        )
    }
)

foreach ($prompt in $globalPrompts) {
    $content = New-GlobalPromptContent -Name $prompt.Name -Description $prompt.Description -Intro $prompt.Intro -WindowsCommands $prompt.WindowsCommands -BashCommands $prompt.BashCommands -ExpectedBehavior $prompt.ExpectedBehavior
    foreach ($promptDir in $promptInstallDirs) {
        $label = Get-PromptScopeLabel -UserRootDir $userRootDir -PromptDirectory $promptDir -PromptName $prompt.Name
        Write-GlobalPrompt -TargetPath (Join-Path $promptDir $prompt.FileName) -Name $prompt.Name -Label $label -Content $content -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
    }
}

# Prompts complejos: se copian directo desde el source (no generados inline)
if (Test-Path $sourcePromptsDir -PathType Container) {
    Get-ChildItem -Path $sourcePromptsDir -Filter '*.prompt.md' -File | Sort-Object Name | ForEach-Object {
        $extraName = $_.BaseName -replace '\.prompt$', ''
        if ($extraName -eq 'start') {
            return
        }

        foreach ($promptDir in $promptInstallDirs) {
            $label = Get-PromptScopeLabel -UserRootDir $userRootDir -PromptDirectory $promptDir -PromptName $extraName
            Copy-TemplateFile -Source $_.FullName -Target (Join-Path $promptDir $_.Name) -Label $label -Overwrite $overwriteExisting -Created $created -Updated $updated -Skipped $skipped
        }
    }
}
else {
    $missing.Add('global-prompts:*.prompt.md')
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

try {
    $hookScriptsAbs = Join-Path $copilotToolsDir 'scripts/hooks'
    $sRef = [ref]$globalHooksStatus
    $dRef = [ref]$globalHooksDetails
    $pRef = [ref]$globalHooksPath
    Sync-GlobalHooks -HookScriptsDir $hookScriptsAbs -StatusRef $sRef -DetailsRef $dRef -PathRef $pRef
    $globalHooksStatus  = $sRef.Value
    $globalHooksDetails = $dRef.Value
    $globalHooksPath    = $pRef.Value
}
catch {
    $globalHooksStatus  = 'WARN'
    $globalHooksDetails = "error en sync hooks globales: $_"
}

try {
    $sRef = [ref]$vscodeSettingsStatus
    $dRef = [ref]$vscodeSettingsDetails
    $pRef = [ref]$vscodeSettingsPath
    Update-VSCodeHookSettings -UserRootDir $userRootDir -StatusRef $sRef -DetailsRef $dRef -PathRef $pRef
    $vscodeSettingsStatus  = $sRef.Value
    $vscodeSettingsDetails = $dRef.Value
    $vscodeSettingsPath    = $pRef.Value
}
catch {
    $vscodeSettingsStatus  = 'WARN'
    $vscodeSettingsDetails = "error actualizando VS Code settings.json: $_"
}

try {
    $sRef = [ref]$legacyClaudeStatus
    $dRef = [ref]$legacyClaudeDetails
    $pRef = [ref]$legacyClaudePath
    Clear-LegacyClaudeManagedHooks -StatusRef $sRef -DetailsRef $dRef -PathRef $pRef
    $legacyClaudeStatus  = $sRef.Value
    $legacyClaudeDetails = $dRef.Value
    $legacyClaudePath    = $pRef.Value
}
catch {
    $legacyClaudeStatus  = 'WARN'
    $legacyClaudeDetails = "error limpiando legacy ~/.claude/settings.json: $_"
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
Write-Output 'Global hooks:'
Write-Output "  - estado: $globalHooksStatus"
Write-Output "  - settings: $globalHooksPath"
Write-Output "  - detalle: $globalHooksDetails"

Write-Output ''
Write-Output 'VS Code hook location:'
Write-Output "  - estado: $vscodeSettingsStatus"
Write-Output "  - settings: $vscodeSettingsPath"
Write-Output "  - detalle: $vscodeSettingsDetails"

Write-Output ''
Write-Output 'Legacy Claude managed hooks cleanup:'
Write-Output "  - estado: $legacyClaudeStatus"
Write-Output "  - settings: $legacyClaudePath"
Write-Output "  - detalle: $legacyClaudeDetails"

Write-Output ''
Write-Output 'Siguiente paso:'
Write-Output '  1. Recarga VS Code / inicia nueva sesion para que los prompts globales y los hooks globales queden activos.'
Write-Output ("  2. Los hooks de orquestacion estan instalados en {0} y aplican a TODOS los proyectos." -f $globalHooksPath)
Write-Output '  3. /start sigue siendo opcional para bootstrap de proyecto (copilot-instructions, stack.md). No es necesario para que los hooks globales funcionen.'
Write-Output ('     Bootstrap manual: & "{0}" .' -f (Join-Path $toolsScriptsDir 'start/start.ps1'))
