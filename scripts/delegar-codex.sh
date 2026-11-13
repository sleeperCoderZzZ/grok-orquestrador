#!/usr/bin/env bash
# Delega uma tarefa ao Codex CLI de forma não interativa (consome a cota ChatGPT/Codex).
# Uso: scripts/delegar-codex.sh "prompt da tarefa" [sandbox]
#   sandbox: read-only (padrão) | workspace-write
# Se USAGE_FILE estiver definido, grava nele o uso de tokens da chamada (JSON).
set -euo pipefail
PROMPT="${1:?uso: delegar-codex.sh \"prompt\" [read-only|workspace-write]}"
SANDBOX="${2:-read-only}"
case "$SANDBOX" in read-only|workspace-write) ;; *) echo "sandbox inválido: $SANDBOX" >&2; exit 2 ;; esac
command -v codex >/dev/null || { echo "codex não encontrado no PATH" >&2; exit 127; }
command -v jq >/dev/null || { echo "jq não encontrado no PATH (necessário para medir uso de tokens)" >&2; exit 127; }

JSONL="$(mktemp)"
trap 'rm -f "$JSONL"' EXIT

set +e
codex exec --json --sandbox "$SANDBOX" --skip-git-repo-check -C "${CODEX_DIR:-$PWD}" "$PROMPT" > "$JSONL"
STATUS=$?
set -e

# Texto final (última mensagem do agente), igual ao que o codex exec sem --json imprimiria.
jq -rs '[.[] | select(.type=="item.completed" and .item.type=="agent_message")] | last | .item.text // empty' "$JSONL"

if [ -n "${USAGE_FILE:-}" ]; then
  jq -cs '[.[] | select(.type=="turn.completed")] | last | .usage // {}' "$JSONL" > "$USAGE_FILE" 2>/dev/null || echo '{}' > "$USAGE_FILE"
fi

exit "$STATUS"
