#!/usr/bin/env pwsh
# Hook: sessionEnd
# Persists valid research cache entries to persistent cache with commit_sha; logs SESSION_END.

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$reason = if ($input_json.reason) { $input_json.reason } else { "unknown" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

$log_path = Join-Path $cwd "session_log.md"
$spans_path = Join-Path $cwd "session_spans.jsonl"

# --- Emit span ---
$span = @{ event_type = "SESSION_END"; timestamp_iso = $ts; reason = $reason } | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8

# --- Persist research cache on clean completion ---
if ($reason -eq "complete") {
    $cache_path = Join-Path $cwd "session-state\research_cache.json"
    $persistent_path = Join-Path $cwd "session-state\research_cache_persistent.json"

    if (Test-Path $cache_path) {
        try {
            $commit_sha = (git -C $cwd rev-parse HEAD 2>$null).Trim()
            if ($commit_sha) {
                $cache = Get-Content $cache_path -Raw | ConvertFrom-Json
                $valid_entries = @($cache | Where-Object { -not $_.stale })

                if ($valid_entries.Count -gt 0) {
                    foreach ($entry in $valid_entries) {
                        $entry | Add-Member -MemberType NoteProperty -Name commit_sha -Value $commit_sha -Force
                    }

                    $persistent = @()
                    if (Test-Path $persistent_path) {
                        try { $persistent = @(Get-Content $persistent_path -Raw | ConvertFrom-Json) } catch {}
                    }

                    $persistent += $valid_entries
                    $persistent | ConvertTo-Json -Depth 10 | Set-Content $persistent_path -Encoding UTF8
                }
            }
        } catch {
            # Non-fatal: log warning only
            Add-Content -Path $log_path -Value "[$date_str] SESSION_END_WARN | cache persistence failed: $_" -Encoding UTF8
        }
    }
}

# --- Log SESSION_END ---
Add-Content -Path $log_path -Value "[$date_str] SESSION_END | reason: $reason" -Encoding UTF8
