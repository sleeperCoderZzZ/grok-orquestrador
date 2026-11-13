# grok-orquestrador

Grok Build como painel de controle, com o **Codex** como cérebro (conector
[`grok-build-providers`](https://github.com/jamubc/grok-build-providers), `grok-codex`)
e o **Claude Code** e o **Codex** como agentes delegados.

## Pré-requisitos (já instalados)
- `grok` (~/.grok/bin), `codex`, `claude`, `grok-codex` (npm global).

## Autenticação (manual, você faz)
```bash
codex login          # conta ChatGPT (OAuth no navegador)
claude               # login da assinatura Anthropic, se ainda não estiver logado
grok login           # opcional; necessário para o Grok nativo
```

## Gemini (Antigravity CLI)
`agy` instalado em `~/.local/bin`. Login: rode `agy` uma vez e conclua o OAuth da conta Google.
Modelos: `agy models`; troque com `GEMINI_MODEL=<id>`.

## Pipeline em fases (sequência)
```bash
scripts/pipeline.sh "descrição da tarefa" /caminho/do/projeto-alvo
```
1. Discovery (Gemini) → 2. Plano (Claude) → 3. Implementação (Codex, escrita só no alvo, sempre confirma)
→ 4. Revisão (Claude) → 5. QA e docs (Gemini). Artefatos em `docs/fases/<timestamp>/`.
`PIPELINE_YES=1` pula as pausas, exceto a da fase 3. Nenhum commit/push é feito.

## Equipes de agentes (uma por fase)
| Fase | Modelo | Papéis (em cadeia; o último consolida) |
|---|---|---|
| 1 Discovery | Gemini | analista-requisitos → analista-riscos |
| 2 Planejamento | Claude | arquiteto → planejador-testes |
| 3 Implementação | Codex | implementador (escreve) → verificador (somente leitura) |
| 4 Revisão | Claude | revisor-seguranca → revisor-qualidade (parecer final) |
| 5 QA e docs | Gemini | engenheiro-qa → redator-tecnico |

- Composição: `equipes/equipes.tsv` (fase, ordem, papel, modelo, modo). Trocar o modelo de um papel é editar uma linha.
- Prompt de cada papel: `equipes/papeis/<papel>.md`; regras Vexur comuns: `equipes/_regras.md`.
- Executor: `scripts/equipe.sh` (usado pelo `pipeline.sh`). `PIPELINE_DRY=1` mostra as equipes sem chamar modelos.
- O wrapper do Gemini o restringe ao diretório do alvo e a comandos de leitura (sem rodar testes/código).
- Uso de tokens: cada chamada real captura o uso de tokens de verdade do próprio CLI (`codex exec --json`,
  `claude --output-format json`, `agy --output-format json`) e grava em `eventos.jsonl`. O painel (`scripts/painel.sh`)
  soma por modelo (entrada/saída/total).

## Uso
```bash
scripts/orquestrar.sh                       # sessão interativa (Codex como cérebro)
scripts/orquestrar.sh -p "tarefa"           # one-shot
scripts/delegar-codex.sh "prompt" [read-only|workspace-write]
scripts/delegar-claude.sh "prompt"
```

## Arquitetura
- `.grok/config.toml` registra o servidor MCP `claude` (`claude mcp serve`).
- O Codex 0.169 não expõe servidor MCP; a delegação a ele é via `codex exec` (script).
- `AGENTS.md` traz as regras de delegação e segurança.

## Notas
- O conector `grok-codex` deve ser iniciado pelo próprio comando; `grok` puro falha com `retrying…`.
- Se houver problema com chamadas de ferramenta, ver `stream_tool_calls = false` no bloco `[model.codex]` (`~/.grok/config.toml`).
- Reinstalar o conector: `grok-build-providers codex`.
