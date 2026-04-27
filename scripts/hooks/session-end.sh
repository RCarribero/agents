#!/usr/bin/env bash
# Hook: sessionEnd
# Persists non-stale research cache entries; logs SESSION_END.
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
reason=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reason','unknown'))" 2>/dev/null || echo "unknown")
date_str=$(date +"%Y-%m-%d %H:%M")

log_path="$cwd/session_log.md"
spans_path="$cwd/session_spans.jsonl"

# --- Emit span ---
printf '{"event_type":"SESSION_END","timestamp_iso":"%s","reason":"%s"}\n' "$ts" "$reason" >> "$spans_path"

# --- Persist cache on complete ---
if [ "$reason" = "complete" ]; then
  cache_path="$cwd/session-state/research_cache.json"
  persistent_path="$cwd/session-state/research_cache_persistent.json"

  if [ -f "$cache_path" ]; then
    commit_sha=$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")
    if [ -n "$commit_sha" ]; then
      python3 - "$cache_path" "$persistent_path" "$commit_sha" "$log_path" "$date_str" <<'PYEOF'
import sys, json, os
cache_path, persistent_path, commit_sha, log_path, date_str = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
try:
    with open(cache_path) as f:
        cache = json.load(f)
    valid = [e for e in cache if not e.get("stale")]
    if not valid:
        sys.exit(0)
    for entry in valid:
        entry["commit_sha"] = commit_sha
    persistent = []
    if os.path.exists(persistent_path):
        try:
            with open(persistent_path) as f:
                persistent = json.load(f)
        except Exception:
            pass
    persistent.extend(valid)
    with open(persistent_path, "w") as f:
        json.dump(persistent, f, indent=2)
except Exception as e:
    with open(log_path, "a") as lf:
        lf.write(f"[{date_str}] SESSION_END_WARN | cache persistence failed: {e}\n")
PYEOF
    fi
  fi
fi

# --- Log ---
echo "[$date_str] SESSION_END | reason: $reason" >> "$log_path"
