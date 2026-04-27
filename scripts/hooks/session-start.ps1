#!/usr/bin/env pwsh
# Hook: sessionStart
# Validates stack.md, inits session_spans.jsonl, invalidates stale research cache, logs SESSION_START

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$source = if ($input_json.source) { $input_json.source } else { "unknown" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

# --- Validate stack.md ---
$stack_exists = Test-Path (Join-Path $cwd "stack.md")
$stack_status = if ($stack_exists) { "OK" } else { "MISSING" }

# --- Init session_spans.jsonl ---
$spans_path = Join-Path $cwd "session_spans.jsonl"
if (-not (Test-Path $spans_path)) {
    New-Item -ItemType File -Path $spans_path -Force | Out-Null
}

# --- Emit sessionStart span ---
$span = @{
    event_type = "SESSION_START"
    timestamp_iso = $ts
    source = $source
    stack_md = $stack_status
    cwd = $cwd
} | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8

# --- Invalidate stale research_cache_persistent entries ---
$persistent_cache = Join-Path $cwd "session-state\research_cache_persistent.json"
if (Test-Path $persistent_cache) {
    try {
        $cache = Get-Content $persistent_cache -Raw | ConvertFrom-Json
        $valid_shas = @{}
        # Build set of known commits
        $git_log = git -C $cwd log --format="%H" 2>$null
        if ($git_log) {
            foreach ($sha in $git_log) { $valid_shas[$sha.Trim()] = $true }
        }
        $changed = $false
        foreach ($entry in $cache) {
            if ($entry.commit_sha -and -not $valid_shas.ContainsKey($entry.commit_sha)) {
                $entry | Add-Member -MemberType NoteProperty -Name stale -Value $true -Force
                $changed = $true
            }
        }
        if ($changed) {
            $cache | ConvertTo-Json -Depth 10 | Set-Content $persistent_cache -Encoding UTF8
        }
    } catch {
        # Non-fatal: cache invalidation failure should not block session
    }
}

# --- Log SESSION_START to session_log.md ---
$log_path = Join-Path $cwd "session_log.md"
$log_entry = "[$date_str] SESSION_START | source: $source | stack.md: $stack_status"
Add-Content -Path $log_path -Value $log_entry -Encoding UTF8
