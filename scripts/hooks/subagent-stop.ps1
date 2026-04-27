#!/usr/bin/env pwsh
# Hook: subagentStop
# Logs SUBAGENT_STOP and emits span.

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

$spans_path = Join-Path $cwd "session_spans.jsonl"
$log_path = Join-Path $cwd "session_log.md"

$span = @{ event_type = "SUBAGENT_STOP"; timestamp_iso = $ts } | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8
Add-Content -Path $log_path -Value "[$date_str] SUBAGENT_STOP" -Encoding UTF8
