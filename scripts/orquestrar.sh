#!/usr/bin/env bash
# Abre o Grok Build com o Codex como cérebro (conector grok-codex) neste projeto.
# O conector sobe o proxy local só enquanto a sessão roda; "grok" puro não funciona com ele.
# Uso: scripts/orquestrar.sh            # sessão interativa
#      scripts/orquestrar.sh -p "tarefa" # one-shot
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.grok/bin:$PATH"
for c in grok-codex codex claude; do
  command -v "$c" >/dev/null || { echo "faltando: $c" >&2; exit 127; }
done
exec grok-codex "$@"
