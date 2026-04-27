#!/usr/bin/env bash
# Hook: userPromptSubmitted
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
prompt=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null || echo "")
date_str=$(date +"%Y-%m-%d %H:%M")

# --- Sanitize + truncate ---
sanitized=$(echo "$prompt" | python3 - <<'PYEOF'
import sys, re
text = sys.stdin.read()
patterns = [
    r'sk-[A-Za-z0-9]{20,}',
    r'ghp_[A-Za-z0-9]{36}',
    r'AKIA[A-Z0-9]{16}',
    r'AIza[0-9A-Za-z\-_]{35}',
    r'xox[bpoa]-[0-9A-Za-z\-]+',
]
for p in patterns:
    text = re.sub(p, '[REDACTED]', text)
preview = text[:200] + '...' if len(text) > 200 else text
print(preview)
PYEOF
)

# --- Emit span ---
spans_path="$cwd/session_spans.jsonl"
span=$(printf '{"event_type":"USER_PROMPT","timestamp_iso":"%s","prompt_preview":"%s"}' \
  "$ts" "$(echo "$sanitized" | head -c 200 | tr -d '\n"')")
echo "$span" >> "$spans_path"

# --- Log ---
log_path="$cwd/session_log.md"
echo "[$date_str] USER_PROMPT | preview: $sanitized" >> "$log_path"
