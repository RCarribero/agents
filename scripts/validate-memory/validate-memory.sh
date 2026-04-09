#!/usr/bin/env bash
# validate-memory.sh
# Verifica el estado de la memoria del sistema:
#   - agents/memoria_global.md existe y tiene al menos 1 entrada
#   - Ningún agente supera 10 notas en AUTONOMOUS_LEARNINGS
#   - session_log.md no supera 500 líneas (si supera: avisa para archivar)
# Salida: estado de cada verificación, warnings si aplica

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_DIR="${1:-$ROOT_DIR/agents}"
SESSION_LOG="${2:-$ROOT_DIR/session_log.md}"
MEMORIA_GLOBAL="$AGENTS_DIR/memoria_global.md"

MAX_LEARNINGS=10
MAX_SESSION_LINES=500

warnings=()
errors=()

echo "=== validate-memory.sh ==="
echo ""

# --- 1. memoria_global.md ---
echo "[1/3] Verificando memoria_global.md"
if [ ! -f "$MEMORIA_GLOBAL" ]; then
  echo "  FAIL: $MEMORIA_GLOBAL no existe"
  errors+=("memoria_global.md no encontrado")
else
  entry_count=$(grep -c "^## \[" "$MEMORIA_GLOBAL" 2>/dev/null || echo "0")
  if [ "$entry_count" -lt 1 ]; then
    echo "  WARN: memoria_global.md existe pero no tiene entradas (## [YYYY-MM-DD])"
    warnings+=("memoria_global.md sin entradas")
  else
    echo "  OK   $entry_count entradas encontradas"
  fi
fi

echo ""

# --- 2. AUTONOMOUS_LEARNINGS por agente ---
echo "[2/3] Verificando AUTONOMOUS_LEARNINGS por agente (máx $MAX_LEARNINGS)"

if [ ! -d "$AGENTS_DIR" ]; then
  echo "  FAIL: directorio '$AGENTS_DIR' no encontrado"
  errors+=("agents/ dir no encontrado")
else
  while IFS= read -r -d '' agent_file; do
    agent_name=$(basename "$agent_file")
    # Extraer notas entre los marcadores
    note_count=$(awk '/AUTONOMOUS_LEARNINGS_START/{f=1; next} /AUTONOMOUS_LEARNINGS_END/{f=0} f && /^- /{count++} END{print count+0}' "$agent_file")

    if [ "$note_count" -gt "$MAX_LEARNINGS" ]; then
      echo "  WARN $agent_name: $note_count notas (supera límite de $MAX_LEARNINGS)"
      warnings+=("$agent_name: $note_count notas en AUTONOMOUS_LEARNINGS — archivar las más antiguas")
    elif [ "$note_count" -ge 1 ]; then
      echo "  OK   $agent_name: $note_count notas"
    else
      echo "  INFO $agent_name: sin notas (0 — esperado para agentes nuevos)"
    fi
  done < <(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -print0 | sort -z)
fi

echo ""

# --- 3. session_log.md ---
echo "[3/3] Verificando session_log.md"
if [ ! -f "$SESSION_LOG" ]; then
  echo "  INFO: $SESSION_LOG no encontrado (no es un error — puede no existir aún)"
else
  line_count=$(wc -l < "$SESSION_LOG")
  if [ "$line_count" -gt "$MAX_SESSION_LINES" ]; then
    echo "  WARN session_log.md: $line_count líneas (supera $MAX_SESSION_LINES — archivar recomendado)"
    warnings+=("session_log.md tiene $line_count líneas — considerar archivar")
  else
    echo "  OK   session_log.md: $line_count líneas"
  fi
fi

echo ""
echo "---"
echo "Resumen: ${#errors[@]} errores, ${#warnings[@]} warnings"

if [ ${#warnings[@]} -gt 0 ]; then
  echo ""
  echo "Warnings:"
  for w in "${warnings[@]}"; do
    echo "  WARN: $w"
  done
fi

if [ ${#errors[@]} -gt 0 ]; then
  echo ""
  echo "Errores:"
  for e in "${errors[@]}"; do
    echo "  ERROR: $e"
  done
  exit 1
fi

exit 0
