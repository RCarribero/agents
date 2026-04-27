#!/usr/bin/env pwsh
# Hook: preToolUse (SECURITY GATE)
# Returns {"permissionDecision":"deny","permissionDecisionReason":"..."} to block tool execution.
# Guards: git write ops (requires devops_authorized), destructive commands, secret leakage.

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$tool_name = if ($input_json.toolName) { $input_json.toolName } else { "" }
$tool_args_raw = if ($input_json.toolArgs) { $input_json.toolArgs } else { "" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

$log_path = Join-Path $cwd "session_log.md"

function Write-Log($msg) {
    try { Add-Content -Path $log_path -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}

function Deny-Tool($reason) {
    Write-Log "[$date_str] PRE_TOOL_DENY | tool: $tool_name | reason: $reason"
    @{ permissionDecision = "deny"; permissionDecisionReason = $reason } | ConvertTo-Json -Compress
    exit 0
}

# Parse toolArgs as JSON if possible
$tool_args = $null
try { $tool_args = $tool_args_raw | ConvertFrom-Json } catch {}

# Collect all text content to scan (command, args, etc.)
$args_str = $tool_args_raw

# --- Secret scan (before any other check) ---
$secret_patterns = @{
    "OpenAI API key"  = 'sk-[A-Za-z0-9]{20,}'
    "GitHub token"    = 'ghp_[A-Za-z0-9]{36}'
    "AWS Access Key"  = 'AKIA[A-Z0-9]{16}'
    "Google API key"  = 'AIza[0-9A-Za-z\-_]{35}'
    "Slack token"     = 'xox[bpoa]-[0-9A-Za-z\-]+'
}
foreach ($label in $secret_patterns.Keys) {
    if ($args_str -match $secret_patterns[$label]) {
        Deny-Tool "Secret detected in tool args: $label"
    }
}

# --- Destructive command block ---
$destructive_patterns = @(
    'rm\s+-rf\s+/',
    'mkfs\.',
    'DROP\s+DATABASE',
    'dd\s+if=.*of=/dev/sd'
)
foreach ($p in $destructive_patterns) {
    if ($args_str -match $p) {
        Deny-Tool "Destructive command blocked: matches pattern '$p'"
    }
}

# --- Git write guard ---
$git_write_pattern = 'git\s+(commit|push|reset\s+--hard|clean\s+-fd)'
if ($args_str -match $git_write_pattern) {
    # Check devops authorization
    $session_state_path = Join-Path $cwd ".copilot-session-state.json"
    $authorized = $false
    if (Test-Path $session_state_path) {
        try {
            $state = Get-Content $session_state_path -Raw | ConvertFrom-Json
            $authorized = [bool]$state.devops_authorized
        } catch {}
    }
    if (-not $authorized) {
        Deny-Tool "Git write operation requires devops_authorized=true in .copilot-session-state.json (git.instructions Regla devops)"
    }
}

# --- Allow: log the tool call ---
Write-Log "[$date_str] PRE_TOOL_ALLOW | tool: $tool_name"
