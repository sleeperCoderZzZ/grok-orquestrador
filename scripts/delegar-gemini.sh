#!/usr/bin/env bash
# Delega uma tarefa ao Gemini via Antigravity CLI (agy), em modo plan (somente leitura).
# Requer login prévio: rode `agy` uma vez e conclua o OAuth da conta Google.
# Uso: scripts/delegar-gemini.sh "prompt da tarefa"
# Modelo: GEMINI_MODEL (padrão gemini-3.8-flash-high). Veja `agy models`.
# Se USAGE_FILE estiver definido, grava nele o uso de tokens da chamada (JSON).
set -euo pipefail
PROMPT="${1:?uso: delegar-gemini.sh \"prompt\"}"
export PATH="$HOME/.local/bin:$PATH"
PROMPT="$PROMPT

Restrição técnica (obrigatória): você só pode LER arquivos (ferramentas de leitura, ls, cat, grep, find, git diff). NÃO execute testes, npm, node, scripts nem qualquer comando que rode código do projeto; se precisar do resultado dos testes, registre como pergunta em aberto. Limite-se ao diretório de trabalho atual (o projeto alvo): NÃO liste nem leia diretórios acima dele nem fora dele."
command -v agy >/dev/null || { echo "agy não encontrado no PATH" >&2; exit 127; }
command -v jq >/dev/null || { echo "jq não encontrado no PATH (necessário para medir uso de tokens)" >&2; exit 127; }
# Permissões só desta sessão (--settings não grava nada): comandos de LEITURA liberados;
# escrita, sudo/rm/curl, git que altera estado e arquivos de segredo ficam negados (deny vence allow).
READ_DIR="${GEMINI_READ_DIR:-$PWD}"   # diretório cuja leitura é liberada (o projeto alvo)
SETTINGS='{"permissions":{
  "allow":["read_file('"$READ_DIR"')","command(ls)","command(cat)","command(grep)","command(find)","command(head)","command(tail)","command(wc)","command(pwd)","command(tree)","command(file)","command(stat)","command(du)","command(sort)","command(test)","command(readlink)","command(basename)","command(dirname)","command(node --version)","command(npm --version)","command(git diff)","command(git status)","command(git log)","command(git show)"],
  "deny":["write_file(*)","command(rm)","command(sudo)","command(regex:curl .*)","command(regex:wget .*)","command(regex:.*(>|>>|tee ).*)","command(regex:.*\\.env.*)","read_file(.env)","read_file(.ssh)","command(regex:git (push|commit|reset|checkout|clean).*)"]
}}'
cd "$READ_DIR"   # o agente explora a partir do alvo e não sai dele (read_file só é liberado nele)

RESP="$(agy --mode plan --output-format json --settings "$SETTINGS" --add-dir "$READ_DIR" --model "${GEMINI_MODEL:-gemini-3.8-flash-high}" --print-timeout 10m -p "$PROMPT")"

echo "$RESP" | jq -r '.response // empty'

if [ -n "${USAGE_FILE:-}" ]; then
  echo "$RESP" | jq -c '.usage // {}' > "$USAGE_FILE" 2>/dev/null || echo '{}' > "$USAGE_FILE"
fi
