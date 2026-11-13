#!/usr/bin/env bash
# Delega uma tarefa ao Claude Code (modo não interativo, somente leitura por padrão).
# Uso: scripts/delegar-claude.sh "prompt da tarefa"
# Se USAGE_FILE estiver definido, grava nele o uso de tokens da chamada (JSON).
set -euo pipefail
PROMPT="${1:?uso: delegar-claude.sh \"prompt\"}"
command -v claude >/dev/null || { echo "claude não encontrado no PATH" >&2; exit 127; }
command -v jq >/dev/null || { echo "jq não encontrado no PATH (necessário para medir uso de tokens)" >&2; exit 127; }

RESP="$(claude -p "$PROMPT" --permission-mode plan --output-format json)"

echo "$RESP" | jq -r '.result // empty'

if [ -n "${USAGE_FILE:-}" ]; then
  echo "$RESP" | jq -c '.usage // {}' > "$USAGE_FILE" 2>/dev/null || echo '{}' > "$USAGE_FILE"
fi
