#!/usr/bin/env bash
# token-report.sh
# Para cada .agent.md en agents/:
#   - Estima tokens (chars / 4)
#   - Avisa si supera 2000 tokens
#   - Muestra total estimado por sesión completa
# Salida: tabla con agente, tokens estimados, warning si aplica

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="${1:-$ROOT_DIR/agents}"
TOKEN_WARN_THRESHOLD=2000

echo "=== token-report.sh ==="
echo "Directorio: $AGENTS_DIR"
echo ""

if [ ! -d "$AGENTS_DIR" ]; then
  echo "ERROR: directorio '$AGENTS_DIR' no encontrado"
  exit 1
fi

total_tokens=0
warn_count=0

# Header de tabla
printf "%-40s %10s %8s\n" "Agente" "Tokens est." "Estado"
printf "%-40s %10s %8s\n" "------" "-----------" "------"

while IFS= read -r -d '' agent_file; do
  agent_name=$(basename "$agent_file")
  char_count=$(wc -c < "$agent_file")
  token_est=$((char_count / 4))
  total_tokens=$((total_tokens + token_est))

  if [ "$token_est" -gt "$TOKEN_WARN_THRESHOLD" ]; then
    status="WARN"
    warn_count=$((warn_count + 1))
  else
    status="OK"
  fi

  printf "%-40s %10d %8s\n" "$agent_name" "$token_est" "$status"
done < <(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -print0 | sort -z)

echo ""
echo "---"
printf "%-40s %10d\n" "TOTAL por sesión completa" "$total_tokens"

echo ""
if [ "$warn_count" -gt 0 ]; then
  echo "WARN: $warn_count agente(s) superan los $TOKEN_WARN_THRESHOLD tokens estimados."
  echo "      Considera condensar las secciones de AUTONOMOUS_LEARNINGS o los ejemplos de contrato."
else
  echo "OK: Todos los agentes están dentro del límite de $TOKEN_WARN_THRESHOLD tokens."
fi

exit 0
