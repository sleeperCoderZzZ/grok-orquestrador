#!/usr/bin/env bash
# Painel ao vivo de uso dos modelos. Rode numa aba de terminal separada enquanto o pipeline executa.
# Uso: scripts/painel.sh [RUN_DIR]   (padrão: a execução mais recente em docs/fases/)
# Ctrl+C para sair. Só leitura: não altera nada do pipeline.
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${1:-}"

if [ -z "$RUN" ]; then
  RUN="$(ls -dt "$RAIZ"/docs/fases/*/ 2>/dev/null | head -1 || true)"
fi
[ -n "$RUN" ] && [ -d "$RUN" ] || {
  echo "Nenhuma execução encontrada em docs/fases/. Rode scripts/pipeline.sh primeiro, ou passe o diretório." >&2
  exit 1
}
RUN="${RUN%/}"

echo "Observando: $RUN (Ctrl+C para sair)"
sleep 1
while true; do
  clear
  python3 -I "$RAIZ/scripts/painel.py" "$RUN" "$RAIZ/equipes/equipes.tsv"
  sleep 2
done
