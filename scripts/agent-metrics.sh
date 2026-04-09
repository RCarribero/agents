#!/usr/bin/env bash
# agent-metrics.sh — Muestra métricas del sistema multi-agente desde Supabase
# Uso: ./scripts/agent-metrics.sh [--json] [--task <task_id>]
#
# Requiere: SUPABASE_URL, SUPABASE_KEY (service_role) o AGENTS_API_URL en .env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar .env si existe
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

JSON_OUTPUT=false
TASK_ID=""
ENDPOINT="summary"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)    JSON_OUTPUT=true ;;
    --task)    shift; TASK_ID="$1"; ENDPOINT="tasks/$TASK_ID" ;;
    --agents)  ENDPOINT="agents" ;;
    *) ;;
  esac
  shift
done

# Verificar configuración
if [[ -z "${AGENTS_API_URL:-}" && -z "${SUPABASE_URL:-}" ]]; then
  echo '{"error":"AGENTS_API_URL o SUPABASE_URL requerido","metrics":[]}'
  exit 1
fi

BASE_URL="${AGENTS_API_URL:-http://localhost:8000}"
AUTH_HEADER=""
if [[ -n "${AGENTS_API_KEY:-}" ]]; then
  AUTH_HEADER="Authorization: Bearer ${AGENTS_API_KEY}"
fi

# Llamar a la API
if command -v curl &>/dev/null; then
  RESPONSE=$(curl -sf \
    ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
    "$BASE_URL/metrics/$ENDPOINT" 2>&1) || {
    echo "{\"error\":\"No se pudo conectar a $BASE_URL/metrics/$ENDPOINT\"}"
    exit 1
  }
else
  echo '{"error":"curl no disponible"}'
  exit 1
fi

if $JSON_OUTPUT; then
  echo "$RESPONSE"
  exit 0
fi

# Formato tabular legible
echo ""
echo "═══════════════════════════════════════════════════"
echo "   MÉTRICAS DEL SISTEMA MULTI-AGENTE v3            "
echo "═══════════════════════════════════════════════════"
echo ""

if [[ -n "$TASK_ID" ]]; then
  echo "  Task ID: $TASK_ID"
  echo ""
  # Extraer y mostrar eventos con python si disponible
  if command -v python3 &>/dev/null; then
    echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
events = data.get('events', [])
if not events:
    print('  Sin eventos para este task_id.')
else:
    print(f'  Total eventos: {len(events)}')
    print('')
    for e in events:
        ts = e.get('timestamp', '')[:19]
        from_a = e.get('from_agent', '?')
        to_a = e.get('to_agent', '?')
        status = e.get('status', '?')
        etype = e.get('event_type', '')
        symbol = '✓' if status == 'SUCCESS' else '✗' if status in ('FAILED', 'REJECT') else '!'
        print(f'  {symbol} [{ts}] {from_a} → {to_a} [{status}] {etype}')
"
  else
    echo "$RESPONSE"
  fi
else
  if command -v python3 &>/dev/null; then
    echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)

# Summary
total = data.get('total_events', 'N/A')
generated = data.get('generated_at', '')[:19]
print(f'  Total eventos registrados : {total}')
print(f'  Generado en               : {generated}')
print('')

# Agent metrics
metrics = data.get('agent_metrics', [])
if metrics:
    print('  RENDIMIENTO POR AGENTE:')
    print(f'  {\"Agente\":<20} {\"Éxito %\":>8} {\"Transiciones\":>14} {\"Escaladas\":>10} {\"Rechazadas\":>11}')
    print('  ' + '-'*65)
    for m in metrics:
        agent = m.get('from_agent', '?')
        rate = m.get('success_rate_pct', 0)
        total_t = m.get('total_transitions', 0)
        esc = m.get('escalated', 0)
        rej = m.get('rejected', 0)
        bar = '█' * int(rate / 10) + '░' * (10 - int(rate / 10))
        print(f'  {agent:<20} {rate:>7.1f}% {total_t:>14} {esc:>10} {rej:>11}  {bar}')
    print('')

# Recent escalations
escals = data.get('recent_escalations', [])
if escals:
    print('  ÚLTIMAS ESCALACIONES:')
    for e in escals:
        ts = e.get('timestamp', '')[:19]
        agent = e.get('from_agent', '?')
        notes = e.get('notes', '')[:60]
        print(f'  ! [{ts}] {agent}: {notes}')
"
  else
    echo "$RESPONSE"
  fi
fi

echo ""
echo "═══════════════════════════════════════════════════"
