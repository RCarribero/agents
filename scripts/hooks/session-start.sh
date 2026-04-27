#!/usr/bin/env bash
# Hook: sessionStart
set -euo pipefail

input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
source_val=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('source','unknown'))" 2>/dev/null || echo "unknown")
date_str=$(date +"%Y-%m-%d %H:%M")

# --- Validate stack.md ---
if [ -f "$cwd/stack.md" ]; then
  stack_status="OK"
else
  stack_status="MISSING"
fi

# --- Init session_spans.jsonl ---
spans_path="$cwd/session_spans.jsonl"
if [ ! -f "$spans_path" ]; then
  touch "$spans_path"
fi

# --- Emit span ---
span=$(printf '{"event_type":"SESSION_START","timestamp_iso":"%s","source":"%s","stack_md":"%s","cwd":"%s"}' \
  "$ts" "$source_val" "$stack_status" "$cwd")
echo "$span" >> "$spans_path"

# --- Invalidate stale persistent cache entries ---
persistent_cache="$cwd/session-state/research_cache_persistent.json"
if [ -f "$persistent_cache" ]; then
  known_shas=$(git -C "$cwd" log --format="%H" 2>/dev/null || true)
  python3 - "$persistent_cache" "$known_shas" <<'PYEOF'
import sys, json
path = sys.argv[1]
known_shas = set(sys.argv[2].strip().splitlines()) if len(sys.argv) > 2 else set()
try:
    with open(path) as f:
        cache = json.load(f)
    changed = False
    for entry in cache:
        sha = entry.get("commit_sha", "")
        if sha and sha not in known_shas:
            entry["stale"] = True
            changed = True
    if changed:
        with open(path, "w") as f:
            json.dump(cache, f, indent=2)
except Exception:
    pass
PYEOF
fi

# --- Log SESSION_START ---
log_path="$cwd/session_log.md"
echo "[$date_str] SESSION_START | source: $source_val | stack.md: $stack_status" >> "$log_path"
