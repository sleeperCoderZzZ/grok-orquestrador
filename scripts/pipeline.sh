#!/usr/bin/env bash
# Pipeline de desenvolvimento em sequência: uma EQUIPE de agentes por fase (ver equipes/equipes.tsv).
#
#   1 Discovery            -> Gemini : analista-requisitos, analista-riscos      (leitura)
#   2 Planejamento         -> Claude : arquiteto, planejador-testes              (leitura)
#   3 Implementação        -> Codex  : implementador (ESCRITA), verificador      (leitura)
#   4 Revisão              -> Claude : revisor-seguranca, revisor-qualidade      (leitura)
#   5 QA e documentação    -> Gemini : engenheiro-qa, redator-tecnico            (leitura)
#
# Uso: scripts/pipeline.sh "<descrição da tarefa>" <ALVO>
#   ALVO = diretório do projeto a ser analisado/alterado (obrigatório, deve existir).
# Variáveis: GEMINI_MODEL, PIPELINE_YES=1 (pula a pausa entre fases, exceto a fase 3),
#            PIPELINE_DRY=1 (mostra as equipes e os tamanhos dos prompts, sem chamar modelos).
# Artefatos: docs/fases/<timestamp>/NN-*.md (fase) e equipe-<fase>-<ordem>-<papel>.md (por papel)
# Regras: nenhum commit/push é feito; só o implementador (fase 3) escreve, e sempre com confirmação.
set -euo pipefail

TAREFA_ARG="${1:?uso: pipeline.sh \"<tarefa ou caminho de um arquivo/pasta com a tarefa>\" <ALVO>}"
# Se o 1º argumento for um arquivo existente, a tarefa é o conteúdo dele; se for uma pasta com
# exatamente um arquivo, idem; caso contrário (ou pasta ambígua), a tarefa é o texto literal.
if [ -f "$TAREFA_ARG" ]; then
  TAREFA="$(cat "$TAREFA_ARG")"
elif [ -d "$TAREFA_ARG" ]; then
  mapfile -t _arqs_tarefa < <(find "$TAREFA_ARG" -maxdepth 1 -type f)
  if [ "${#_arqs_tarefa[@]}" -eq 1 ]; then
    TAREFA="$(cat "${_arqs_tarefa[0]}")"
  else
    echo "Aviso: '$TAREFA_ARG' é uma pasta com ${#_arqs_tarefa[@]} arquivo(s); usando o caminho como texto literal da tarefa." >&2
    TAREFA="$TAREFA_ARG"
  fi
elif [[ "$TAREFA_ARG" == */* || "$TAREFA_ARG" == *.md ]]; then
  echo "ERRO: '$TAREFA_ARG' parece um caminho de arquivo/pasta, mas não existe. Confira o nome (maiúsculas/minúsculas, sufixos) com: find . -iname '*$(basename "$TAREFA_ARG" .md)*'" >&2
  exit 1
else
  TAREFA="$TAREFA_ARG"
fi
ALVO="$(cd "${2:?uso: pipeline.sh \"<tarefa>\" <ALVO>}" && pwd)"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$RAIZ/docs/fases/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
exec 3<&0   # stdin original reservado para as confirmações; os agentes recebem /dev/null
echo "$TAREFA" > "$RUN/00-tarefa.md"
echo "Alvo: $ALVO"
echo "Artefatos: $RUN"
[ "${PIPELINE_DRY:-0}" = "1" ] && echo "(modo dry-run: nenhum modelo será chamado)"

# shellcheck source=equipe.sh
source "$RAIZ/scripts/equipe.sh"

confirmar() { # $1 = mensagem, $2 = "sempre" para ignorar PIPELINE_YES
  if [ "${PIPELINE_DRY:-0}" = "1" ]; then return 0; fi
  if [ "${2:-}" != "sempre" ] && [ "${PIPELINE_YES:-0}" = "1" ]; then return 0; fi
  read -r -u 3 -p "$1 [s/N] " r || { echo "Sem resposta (stdin fechado); interrompendo em: $1"; exit 0; }
  [ "$r" = "s" ] || [ "$r" = "S" ] || { echo "Pipeline interrompido em: $1"; exit 0; }
}

echo; echo "== Fase 1: Discovery =="
confirmar "Executar a fase 1?"
rodar_equipe 1 "$RUN/01-requisitos.md"

echo; echo "== Fase 2: Planejamento =="
confirmar "Executar a fase 2?"
rodar_equipe 2 "$RUN/02-plano.md" "$RUN/01-requisitos.md"

echo; echo "== Fase 3: Implementação (ESCRITA em $ALVO) =="
confirmar "Autorizar o Codex a ESCREVER em $ALVO (sem commit/push)?" sempre
rodar_equipe 3 "$RUN/03-implementacao.md" "$RUN/02-plano.md"

echo; echo "== Fase 4: Revisão =="
confirmar "Executar a fase 4?"
{ echo "git diff do alvo (truncado):"; git -C "$ALVO" diff 2>/dev/null | head -c 60000 || true; } > "$RUN/04-diff.txt"
rodar_equipe 4 "$RUN/04-revisao.md" "$RUN/02-plano.md" "$RUN/03-implementacao.md" "$RUN/04-diff.txt"

echo; echo "== Fase 5: QA e documentação =="
confirmar "Executar a fase 5?"
rodar_equipe 5 "$RUN/05-qa-docs.md" "$RUN/02-plano.md" "$RUN/04-revisao.md"

echo; echo "Pipeline concluído. Artefatos em $RUN"
