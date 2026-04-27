#!/usr/bin/env pwsh
# Hook: errorOccurred
# Logs error, emits span, updates MCP circuit breaker, tracks error patterns.

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$error_obj = $input_json.error
$err_message = if ($error_obj -and $error_obj.message) { $error_obj.message } else { "unknown" }
$err_name = if ($error_obj -and $error_obj.name) { $error_obj.name } else { "" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

$log_path = Join-Path $cwd "session_log.md"
$spans_path = Join-Path $cwd "session_spans.jsonl"
$mcp_state_path = Join-Path $cwd ".copilot-mcp-state.json"
$error_patterns_path = Join-Path $cwd ".copilot-error-patterns.json"

# --- Emit span ---
$span = @{
    event_type = "ERROR"
    timestamp_iso = $ts
    error_name = $err_name
    error_message = $err_message.Substring(0, [Math]::Min($err_message.Length, 200))
} | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8

# --- Log error ---
Add-Content -Path $log_path -Value "[$date_str] ERROR | $err_name: $($err_message.Substring(0,[Math]::Min($err_message.Length,200)))" -Encoding UTF8

# --- MCP circuit breaker update on MCP errors ---
$mcp_keywords = @('mcp', 'supabase', 'github-mcp', 'vercel-mcp', 'stripe-mcp')
$is_mcp_error = $mcp_keywords | Where-Object { $err_message -like "*$_*" -or $err_name -like "*$_*" }
if ($is_mcp_error) {
    $mcp_state = @{}
    if (Test-Path $mcp_state_path) {
        try { $mcp_state = Get-Content $mcp_state_path -Raw | ConvertFrom-Json -AsHashtable } catch {}
    }
    $mcp_key = "mcp_error_general"
    if (-not $mcp_state.ContainsKey($mcp_key)) {
        $mcp_state[$mcp_key] = @{ fail_count = 0; state = "CLOSED" }
    }
    $mcp_state[$mcp_key].fail_count += 1
    if ($mcp_state[$mcp_key].fail_count -ge 2 -and $mcp_state[$mcp_key].state -ne "OPEN") {
        $mcp_state[$mcp_key].state = "OPEN"
        $mcp_state[$mcp_key].opened_at = $ts
        Add-Content -Path $log_path -Value "[$date_str] MCP_CIRCUIT_CHANGE | key: $mcp_key | state: OPEN (error hook)" -Encoding UTF8
    }
    $mcp_state | ConvertTo-Json -Depth 5 | Set-Content $mcp_state_path -Encoding UTF8
}

# --- Track error patterns (last 50) ---
$patterns = @()
if (Test-Path $error_patterns_path) {
    try { $patterns = @(Get-Content $error_patterns_path -Raw | ConvertFrom-Json) } catch {}
}
$patterns += @{ ts = $ts; name = $err_name; message = $err_message.Substring(0, [Math]::Min($err_message.Length, 150)) }
if ($patterns.Count -gt 50) { $patterns = $patterns[-50..-1] }
$patterns | ConvertTo-Json -Depth 5 | Set-Content $error_patterns_path -Encoding UTF8
