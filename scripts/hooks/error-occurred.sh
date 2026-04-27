#!/usr/bin/env bash
# Hook: errorOccurred
# Logs error, emits span, updates MCP circuit breaker, tracks error patterns.
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
err_message=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('message','unknown') if isinstance(e,dict) else 'unknown')" 2>/dev/null || echo "unknown")
err_name=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('error',{}); print(e.get('name','') if isinstance(e,dict) else '')" 2>/dev/null || echo "")
date_str=$(date +"%Y-%m-%d %H:%M")

log_path="$cwd/session_log.md"
spans_path="$cwd/session_spans.jsonl"
mcp_state_path="$cwd/.copilot-mcp-state.json"
error_patterns_path="$cwd/.copilot-error-patterns.json"

# --- Emit span ---
err_preview=$(echo "$err_message" | head -c 200 | tr -d '\n"')
printf '{"event_type":"ERROR","timestamp_iso":"%s","error_name":"%s","error_message":"%s"}\n' \
  "$ts" "$err_name" "$err_preview" >> "$spans_path"

# --- Log error ---
echo "[$date_str] ERROR | $err_name: $(echo "$err_message" | head -c 200)" >> "$log_path"

# --- MCP circuit breaker + error patterns ---
python3 - "$mcp_state_path" "$error_patterns_path" "$err_name" "$err_message" "$ts" "$log_path" "$date_str" <<'PYEOF'
import sys, json, os, re
state_path, patterns_path, err_name, err_message, ts, log_path, date_str = sys.argv[1:]

# MCP circuit breaker
mcp_keywords = ['mcp', 'supabase', 'github-mcp', 'vercel-mcp', 'stripe-mcp']
is_mcp = any(kw in err_message.lower() or kw in err_name.lower() for kw in mcp_keywords)
if is_mcp:
    state = {}
    if os.path.exists(state_path):
        try:
            with open(state_path) as f:
                state = json.load(f)
        except Exception:
            pass
    key = "mcp_error_general"
    if key not in state:
        state[key] = {"fail_count": 0, "state": "CLOSED"}
    state[key]["fail_count"] = state[key].get("fail_count", 0) + 1
    if state[key]["fail_count"] >= 2 and state[key].get("state") != "OPEN":
        state[key]["state"] = "OPEN"
        state[key]["opened_at"] = ts
        with open(log_path, "a") as lf:
            lf.write(f"[{date_str}] MCP_CIRCUIT_CHANGE | key: {key} | state: OPEN (error hook)\n")
    with open(state_path, "w") as f:
        json.dump(state, f, indent=2)

# Error patterns tracking (last 50)
patterns = []
if os.path.exists(patterns_path):
    try:
        with open(patterns_path) as f:
            patterns = json.load(f)
    except Exception:
        pass
patterns.append({"ts": ts, "name": err_name, "message": err_message[:150]})
patterns = patterns[-50:]
with open(patterns_path, "w") as f:
    json.dump(patterns, f, indent=2)
PYEOF
