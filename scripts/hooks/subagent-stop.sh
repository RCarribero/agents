#!/usr/bin/env bash
# Hook: subagentStop
set -euo pipefail
input_json=$(cat)
ts=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
cwd=$(echo "$input_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || pwd)
date_str=$(date +"%Y-%m-%d %H:%M")
printf '{"event_type":"SUBAGENT_STOP","timestamp_iso":"%s"}\n' "$ts" >> "$cwd/session_spans.jsonl"
echo "[$date_str] SUBAGENT_STOP" >> "$cwd/session_log.md"
