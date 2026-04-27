#!/usr/bin/env bash
# Hook: postToolUse
# Emits span, updates MCP circuit breaker, invalidates research cache.
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
tool_name=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('toolName',''))" 2>/dev/null || echo "")
tool_args=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('toolArgs',''))" 2>/dev/null || echo "")
result_type=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); tr=d.get('toolResult',{}); print(tr.get('resultType','unknown') if isinstance(tr,dict) else 'unknown')" 2>/dev/null || echo "unknown")
date_str=$(date +"%Y-%m-%d %H:%M")

spans_path="$cwd/session_spans.jsonl"
log_path="$cwd/session_log.md"
mcp_state_path="$cwd/.copilot-mcp-state.json"

# --- Emit span ---
span=$(printf '{"event_type":"POST_TOOL","timestamp_iso":"%s","tool":"%s","result_type":"%s"}' \
  "$ts" "$tool_name" "$result_type")
echo "$span" >> "$spans_path"

# --- MCP circuit breaker ---
if echo "$tool_name" | grep -qE 'mcp_(github|supabase|vercel|stripe|resend)'; then
  python3 - "$mcp_state_path" "$tool_name" "$result_type" "$ts" "$log_path" "$date_str" <<'PYEOF'
import sys, json, os
state_path, tool, result, ts, log_path, date_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
state = {}
if os.path.exists(state_path):
    try:
        with open(state_path) as f:
            state = json.load(f)
    except Exception:
        pass
if tool not in state:
    state[tool] = {"fail_count": 0, "state": "CLOSED"}
if result in ("error", "failure"):
    state[tool]["fail_count"] = state[tool].get("fail_count", 0) + 1
    if state[tool]["fail_count"] >= 2 and state[tool].get("state") != "OPEN":
        state[tool]["state"] = "OPEN"
        state[tool]["opened_at"] = ts
        with open(log_path, "a") as lf:
            lf.write(f"[{date_str}] MCP_CIRCUIT_CHANGE | tool: {tool} | state: OPEN | fail_count: {state[tool]['fail_count']}\n")
else:
    state[tool]["fail_count"] = 0
    state[tool]["state"] = "CLOSED"
with open(state_path, "w") as f:
    json.dump(state, f, indent=2)
PYEOF
fi

# --- Research cache invalidation ---
cache_path="$cwd/session-state/research_cache.json"
if [ "$result_type" != "error" ] && [ "$result_type" != "failure" ] && \
   echo "$tool_name" | grep -qE '^(edit|create|write)$' && [ -f "$cache_path" ]; then
  changed_path=$(echo "$tool_args" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('path',''))" 2>/dev/null || echo "")
  if [ -n "$changed_path" ]; then
    python3 - "$cache_path" "$changed_path" <<'PYEOF'
import sys, json
path, changed = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cache = json.load(f)
    modified = False
    for entry in cache:
        if changed in entry.get("relevant_files", []):
            entry["stale"] = True
            modified = True
    if modified:
        with open(path, "w") as f:
            json.dump(cache, f, indent=2)
except Exception:
    pass
PYEOF
  fi
fi
