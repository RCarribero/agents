#!/usr/bin/env pwsh
# Hook: userPromptSubmitted
# Sanitizes and logs the user prompt; emits span; redacts secret patterns

$input_json = $input | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
$ts = if ($input_json.timestamp) { $input_json.timestamp } else { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") }
$cwd = if ($input_json.cwd) { $input_json.cwd } else { $PWD.Path }
$prompt = if ($input_json.prompt) { $input_json.prompt } else { "" }
$date_str = (Get-Date -Format "yyyy-MM-dd HH:mm")

# --- Secret patterns to redact ---
$secret_patterns = @(
    'sk-[A-Za-z0-9]{20,}',           # OpenAI
    'ghp_[A-Za-z0-9]{36}',           # GitHub Personal Access Token
    'AKIA[A-Z0-9]{16}',              # AWS Access Key
    'AIza[0-9A-Za-z\-_]{35}',        # Google API Key
    'xox[bpoa]-[0-9A-Za-z\-]+'       # Slack token
)

$sanitized = $prompt
foreach ($pattern in $secret_patterns) {
    $sanitized = $sanitized -replace $pattern, "[REDACTED]"
}

# --- Truncate for log (max 200 chars) ---
$preview = if ($sanitized.Length -gt 200) { $sanitized.Substring(0, 200) + "..." } else { $sanitized }

# --- Emit span ---
$spans_path = Join-Path $cwd "session_spans.jsonl"
$span = @{
    event_type = "USER_PROMPT"
    timestamp_iso = $ts
    prompt_preview = $preview
} | ConvertTo-Json -Compress
Add-Content -Path $spans_path -Value $span -Encoding UTF8

# --- Log to session_log.md ---
$log_path = Join-Path $cwd "session_log.md"
$log_entry = "[$date_str] USER_PROMPT | preview: $preview"
Add-Content -Path $log_path -Value $log_entry -Encoding UTF8
