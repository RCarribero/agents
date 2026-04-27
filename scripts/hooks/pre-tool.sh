#!/usr/bin/env bash
# Hook: preToolUse (SECURITY GATE)
# Output {"permissionDecision":"deny","permissionDecisionReason":"..."} to block.
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
tool_name=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('toolName',''))" 2>/dev/null || echo "")
tool_args=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('toolArgs',''))" 2>/dev/null || echo "")
date_str=$(date +"%Y-%m-%d %H:%M")
log_path="$cwd/session_log.md"

deny() {
  local reason="$1"
  echo "[$date_str] PRE_TOOL_DENY | tool: $tool_name | reason: $reason" >> "$log_path"
  # JSON-escape reason
  local esc
  esc=$(printf '%s' "$reason" | python3 -c "import sys,json; sys.stdout.write(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$reason")
  printf '{"permissionDecision":"deny","permissionDecisionReason":%s,"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' "$esc" "$esc"
  exit 0
}

# --- Secret scan ---
secret_found=$(python3 - "$tool_args" 2>/dev/null <<'PYEOF'
import sys, re
text = sys.argv[1] if len(sys.argv) > 1 else ""
patterns = {
    "OpenAI API key": r'sk-[A-Za-z0-9]{20,}',
    "GitHub token":   r'ghp_[A-Za-z0-9]{36}',
    "AWS Access Key": r'AKIA[A-Z0-9]{16}',
    "Google API key": r'AIza[0-9A-Za-z\-_]{35}',
    "Slack token":    r'xox[bpoa]-[0-9A-Za-z\-]+',
}
for label, p in patterns.items():
    if re.search(p, text):
        print(label)
        import sys; sys.exit(0)
PYEOF
) || true
if [ -n "$secret_found" ]; then
  deny "Secret detected in tool args: $secret_found"
fi

# --- Destructive command block ---
if echo "$tool_args" | grep -qEi 'rm\s+-rf\s+/|mkfs\.|DROP\s+DATABASE|dd\s+if=.*of=/dev/sd'; then
  deny "Destructive command blocked"
fi

# --- Git write guard ---
if echo "$tool_args" | grep -qE 'git\s+(commit|push|reset\s+--hard|clean\s+-fd)'; then
  authorized="false"
  session_state="$cwd/.copilot-session-state.json"
  if [ -f "$session_state" ]; then
    authorized=$(python3 - "$session_state" 2>/dev/null <<'PYEOF' || echo "false"
import sys, json
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    print('true' if d.get('devops_authorized') else 'false')
except Exception:
    print('false')
PYEOF
)
  fi
  if [ "$authorized" != "true" ]; then
    deny "Git write requires devops_authorized=true in .copilot-session-state.json"
  fi
fi

# --- Allow ---
echo "[$date_str] PRE_TOOL_ALLOW | tool: $tool_name" >> "$log_path"
