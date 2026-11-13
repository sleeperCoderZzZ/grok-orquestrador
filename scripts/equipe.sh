#!/usr/bin/env bash
# Biblioteca (use com `source`): executa a equipe de agentes de uma fase.
# A composição das equipes fica em equipes/equipes.tsv; o prompt de cada papel em equipes/papeis/<papel>.md.
#
# Variáveis esperadas: RAIZ, ALVO, TAREFA, RUN. Opcional: PIPELINE_DRY=1 (não chama modelos).
#
# rodar_equipe <fase> <arquivo-final> [arquivos-de-entrada...]
#   Cada papel da fase roda em sequência (ordem do .tsv), recebendo as entradas da fase e a saída do
#   papel anterior. O arquivo final contém a saída de todos os papéis; a de cada papel fica também em
#   $RUN/equipe-<fase>-<ordem>-<papel>.md.
#
# Cada chamada grava um evento em $RUN/eventos.jsonl (lido pelo painel, scripts/painel.sh).

registrar_evento() { # evento fase ordem papel modelo modo status duracao_s bytes tokens_in tokens_out tokens_cache tokens_total
  local ev="$1" fa="$2" ord="$3" pap="$4" mod="$5" mo="$6" st="$7" du="$8" by="$9"
  local ti="${10:-0}" to="${11:-0}" tc="${12:-0}" tt="${13:-0}"
  printf '{"ts":"%s","evento":"%s","fase":%s,"ordem":%s,"papel":"%s","modelo":"%s","modo":"%s","status":"%s","duracao_s":%s,"bytes":%s,"tokens_in":%s,"tokens_out":%s,"tokens_cache":%s,"tokens_total":%s}\n' \
    "$(date -Iseconds)" "$ev" "$fa" "$ord" "$pap" "$mod" "$mo" "$st" "$du" "$by" "$ti" "$to" "$tc" "$tt" >> "$RUN/eventos.jsonl"
}

# normalizar_uso <modelo> <arquivo-json-bruto-do-delegar-*.sh>
# Cada CLI (codex/claude/agy) reporta o uso de tokens com campos diferentes; isto
# padroniza para {tokens_in, tokens_out, tokens_cache, tokens_total}, sempre em stdout.
normalizar_uso() {
  local modelo="$1" arq="$2" vazio='{"tokens_in":0,"tokens_out":0,"tokens_cache":0,"tokens_total":0}'
  [ -s "$arq" ] || { echo "$vazio"; return; }
  case "$modelo" in
    codex)
      jq -c '{tokens_in: (.input_tokens // 0),
              tokens_out: ((.output_tokens // 0) + (.reasoning_output_tokens // 0)),
              tokens_cache: (.cached_input_tokens // 0),
              tokens_total: ((.input_tokens // 0) + (.output_tokens // 0) + (.reasoning_output_tokens // 0))}' \
        "$arq" 2>/dev/null || echo "$vazio" ;;
    claude)
      jq -c '{tokens_in: ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)),
              tokens_out: (.output_tokens // 0),
              tokens_cache: (.cache_read_input_tokens // 0),
              tokens_total: ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0))}' \
        "$arq" 2>/dev/null || echo "$vazio" ;;
    gemini)
      jq -c '{tokens_in: (.input_tokens // 0),
              tokens_out: (.output_tokens // 0),
              tokens_cache: (.cache_read_tokens // 0),
              tokens_total: (.total_tokens // ((.input_tokens // 0) + (.output_tokens // 0)))}' \
        "$arq" 2>/dev/null || echo "$vazio" ;;
    *) echo "$vazio" ;;
  esac
}

validar_saida() { # $1 = arquivo; devolve "ok" | "vazio" | "erro_permissao" via stdout, nunca sai do script
  if grep -q 'no output produced' "$1" 2>/dev/null; then
    echo "erro_permissao"
  elif [ ! -s "$1" ]; then
    echo "vazio"
  else
    echo "ok"
  fi
}

rodar_equipe() {
  local fase="$1" final="$2"; shift 2
  local tsv="$RAIZ/equipes/equipes.tsv" entradas="" f anterior="" achou=0
  local ctx="Contexto do projeto alvo: $ALVO."
  for f in "$@"; do
    entradas+=$'\n'"### Entrada: $(basename "$f")"$'\n'"$(cat "$f")"$'\n'
  done
  : > "$final"

  while IFS=$'\t' read -r fs ordem papel modelo modo; do
    case "$fs" in ''|'#'*) continue ;; esac
    [ "$fs" = "$fase" ] || continue
    achou=1
    local arq_papel="$RAIZ/equipes/papeis/$papel.md" saida="$RUN/equipe-$fase-$ordem-$papel.md"
    [ -f "$arq_papel" ] || { echo "ERRO: papel sem prompt: $arq_papel" >&2; exit 1; }

    local prompt
    prompt="$(cat "$RAIZ/equipes/_regras.md")

# Seu papel: $papel (equipe da fase $fase, posição $ordem)
$(cat "$arq_papel")

$ctx
## Tarefa
$TAREFA
$entradas
## Trabalho do papel anterior nesta fase
${anterior:-(você é o primeiro papel da fase)}"

    echo; echo "-- Fase $fase / $ordem: $papel [$modelo${modo:+/$modo}] --"
    if [ "${PIPELINE_DRY:-0}" = "1" ]; then
      echo "(dry-run) prompt com ${#prompt} caracteres; nenhum modelo foi chamado."
      echo "[dry-run] $papel ($modelo/$modo)" > "$saida"
    else
      local t0 t1 dur status
      local usage_file="$RUN/.usage-$fase-$ordem.json"
      rm -f "$usage_file"
      t0=$(date +%s.%N)
      registrar_evento "inicio" "$fase" "$ordem" "$papel" "$modelo" "$modo" "" null null
      case "$modelo" in
        gemini) GEMINI_READ_DIR="$ALVO" USAGE_FILE="$usage_file" "$RAIZ/scripts/delegar-gemini.sh" "$prompt" < /dev/null | tee "$saida" ;;
        claude) USAGE_FILE="$usage_file" "$RAIZ/scripts/delegar-claude.sh" "$prompt" < /dev/null | tee "$saida" ;;
        codex)  CODEX_DIR="$ALVO" USAGE_FILE="$usage_file" "$RAIZ/scripts/delegar-codex.sh" "$prompt" "${modo:-read-only}" < /dev/null | tee "$saida" ;;
        *) echo "ERRO: modelo desconhecido '$modelo' em equipes.tsv" >&2; exit 1 ;;
      esac
      t1=$(date +%s.%N)
      dur=$(LC_NUMERIC=C awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')
      status=$(validar_saida "$saida")
      local uso ti to_ tc tt
      uso="$(normalizar_uso "$modelo" "$usage_file")"
      rm -f "$usage_file"
      ti="$(echo "$uso" | jq -r '.tokens_in // 0')"
      to_="$(echo "$uso" | jq -r '.tokens_out // 0')"
      tc="$(echo "$uso" | jq -r '.tokens_cache // 0')"
      tt="$(echo "$uso" | jq -r '.tokens_total // 0')"
      registrar_evento "fim" "$fase" "$ordem" "$papel" "$modelo" "$modo" "$status" "$dur" "$(wc -c < "$saida" 2>/dev/null || echo 0)" "$ti" "$to_" "$tc" "$tt"
      [ "$status" = "ok" ] || { echo "ERRO: o agente não produziu saída útil ($saida, status=$status). Interrompendo." >&2; exit 1; }
    fi
    anterior="$(cat "$saida")"
    { echo "## $papel ($modelo)"; echo; cat "$saida"; echo; } >> "$final"
  done < "$tsv"

  [ "$achou" = "1" ] || { echo "ERRO: nenhuma equipe definida para a fase $fase em $tsv" >&2; exit 1; }
}
