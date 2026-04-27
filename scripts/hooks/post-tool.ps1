#!/usr/bin/env pwsh
# Hook: postToolUse
# Emits span, updates MCP circuit breaker, invalidates research cache entries if path overlaps.

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$tool_name = if ($input_json.toolName) { $input_json.toolName } else { "" }
$tool_args_raw = if ($input_json.toolArgs) { $input_json.toolArgs } else { "" }
$tool_result = $input_json.toolResult
$result_type = if ($tool_result -and $tool_result.resultType) { $tool_result.resultType } else { "unknown" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

$spans_path = Join-Path $cwd "session_spans.jsonl"
$log_path = Join-Path $cwd "session_log.md"
$mcp_state_path = Join-Path $cwd ".copilot-mcp-state.json"

# --- Emit span ---
$span = @{
    event_type = "POST_TOOL"
    timestamp_iso = $ts
    tool = $tool_name
    result_type = $result_type
} | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8

# --- MCP circuit breaker ---
$mcp_tools = @('mcp_github', 'mcp_supabase', 'mcp_vercel', 'mcp_stripe', 'mcp_resend')
$is_mcp = $mcp_tools | Where-Object { $tool_name -like "*$_*" }
if ($is_mcp) {
    $mcp_state = @{}
    if (Test-Path $mcp_state_path) {
        try { $mcp_state = Get-Content $mcp_state_path -Raw | ConvertFrom-Json -AsHashtable } catch {}
    }
    if (-not $mcp_state.ContainsKey($tool_name)) {
        $mcp_state[$tool_name] = @{ fail_count = 0; state = "CLOSED" }
    }
    if ($result_type -in @("error", "failure")) {
        $mcp_state[$tool_name].fail_count += 1
        if ($mcp_state[$tool_name].fail_count -ge 2 -and $mcp_state[$tool_name].state -ne "OPEN") {
            $mcp_state[$tool_name].state = "OPEN"
            $mcp_state[$tool_name].opened_at = $ts
            $log_entry = "[$date_str] MCP_CIRCUIT_CHANGE | tool: $tool_name | state: OPEN | fail_count: $($mcp_state[$tool_name].fail_count)"
            Add-Content -Path $log_path -Value $log_entry -Encoding UTF8
        }
    } else {
        # Success: reset
        $mcp_state[$tool_name].fail_count = 0
        $mcp_state[$tool_name].state = "CLOSED"
    }
    $mcp_state | ConvertTo-Json -Depth 5 | Set-Content $mcp_state_path -Encoding UTF8
}

# --- Research cache invalidation ---
$cache_path = Join-Path $cwd "session-state\research_cache.json"
if ($result_type -notin @("error", "failure") -and $tool_name -in @("edit", "create", "write") -and (Test-Path $cache_path)) {
    try {
        $args_parsed = $tool_args_raw | ConvertFrom-Json -ErrorAction Stop
        $changed_path = $args_parsed.path
        if ($changed_path) {
            $cache = Get-Content $cache_path -Raw | ConvertFrom-Json
            $changed = $false
            foreach ($entry in $cache) {
                if ($entry.relevant_files -and ($entry.relevant_files -contains $changed_path)) {
                    $entry | Add-Member -MemberType NoteProperty -Name stale -Value $true -Force
                    $changed = $true
                }
            }
            if ($changed) {
                $cache | ConvertTo-Json -Depth 10 | Set-Content $cache_path -Encoding UTF8
            }
        }
    } catch {}
}
