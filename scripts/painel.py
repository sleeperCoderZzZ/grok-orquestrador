#!/usr/bin/env python3
"""Renderiza uma tabela de uso dos modelos a partir de docs/fases/<execucao>/eventos.jsonl.
Chamado em loop por scripts/painel.sh. Não faz rede nem escreve nada; só lê e imprime.
Uso: painel.py <RUN_DIR> <equipes.tsv>

Tokens: cada chamada real (fase 'fim') já grava tokens_in/tokens_out/tokens_cache/tokens_total,
capturados de verdade dos CLIs (codex exec --json, claude --output-format json, agy --output-format
json) por scripts/delegar-*.sh.
"""
import json
import os
import sys
from datetime import datetime, timezone

def ler_tsv(caminho):
    papeis = []  # [(fase, ordem, papel, modelo, modo)]
    if not os.path.isfile(caminho):
        return papeis
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.rstrip("\n")
            if not linha or linha.startswith("#"):
                continue
            partes = linha.split("\t")
            if len(partes) >= 5:
                papeis.append(tuple(partes[:5]))
    return papeis

def ler_eventos(caminho):
    eventos = []
    if not os.path.isfile(caminho):
        return eventos
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.strip()
            if not linha:
                continue
            try:
                eventos.append(json.loads(linha))
            except json.JSONDecodeError:
                continue
    return eventos

def agora():
    return datetime.now(timezone.utc).astimezone()

def parse_ts(s):
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return agora()

def main():
    run_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    tsv = sys.argv[2] if len(sys.argv) > 2 else ""
    eventos = ler_eventos(os.path.join(run_dir, "eventos.jsonl"))
    roster = ler_tsv(tsv)

    # Tokens reais de verdade, somados de TODAS as chamadas "fim" desta execução (não só a
    # última por posição), já que a mesma posição pode ter sido rodada de novo nesta execução.
    tokens_por_modelo = {}
    for ev in eventos:
        if ev.get("evento") != "fim":
            continue
        modelo = ev.get("modelo")
        if not modelo:
            continue
        acc = tokens_por_modelo.setdefault(modelo, {"total": 0, "in": 0, "out": 0, "chamadas": 0})
        acc["total"] += int(ev.get("tokens_total") or 0)
        acc["in"] += int(ev.get("tokens_in") or 0)
        acc["out"] += int(ev.get("tokens_out") or 0)
        acc["chamadas"] += 1

    # Estado por posição (fase, ordem): pendente | rodando | ok | vazio | erro_permissao
    estado = {}
    duracao = {}
    inicio_em = {}
    for ev in eventos:
        chave = (str(ev.get("fase")), str(ev.get("ordem")))
        if ev.get("evento") == "inicio":
            estado[chave] = "rodando"
            inicio_em[chave] = ev.get("ts")
        elif ev.get("evento") == "fim":
            estado[chave] = ev.get("status", "ok")
            duracao[chave] = ev.get("duracao_s")

    # Agregados por modelo
    modelos = {}  # nome -> dict
    for fase, ordem, papel, modelo, modo in roster:
        d = modelos.setdefault(modelo, {
            "rodando": None, "chamadas": 0, "tempo_total": 0.0, "ultima_duracao": None, "erros": 0,
        })

    for fase, ordem, papel, modelo, modo in roster:
        chave = (fase, ordem)
        st = estado.get(chave, "pendente")
        d = modelos[modelo]
        if st == "rodando":
            d["rodando"] = f"{papel} (fase {fase})"
        if chave in duracao and duracao[chave] is not None:
            d["chamadas"] += 1
            d["tempo_total"] += float(duracao[chave])
            d["ultima_duracao"] = duracao[chave]
        if st in ("vazio", "erro_permissao"):
            d["erros"] += 1

    tarefa_path = os.path.join(run_dir, "00-tarefa.md")
    tarefa = ""
    try:
        with open(tarefa_path, encoding="utf-8") as f:
            linhas = f.read().strip().splitlines()
            tarefa = linhas[0] if linhas else ""
    except OSError:
        tarefa = ""
    if len(tarefa) > 90:
        tarefa = tarefa[:87] + "..."

    print("=== Painel de uso dos modelos — grok-orquestrador ===")
    print(f"Execução: {run_dir}")
    if tarefa:
        print(f"Tarefa:   {tarefa}")
    print(f"Agora:    {agora().strftime('%H:%M:%S')}\n")

    print(f"{'MODELO':<8} {'STATUS':<30} {'CHAMADAS':>8} {'TEMPO TOTAL':>12} {'ÚLTIMA':>8} {'ERROS':>6}")
    for nome in ("gemini", "claude", "codex"):
        if nome not in modelos:
            continue
        d = modelos[nome]
        status = f"rodando: {d['rodando']}" if d["rodando"] else "ocioso"
        if len(status) > 30:
            status = status[:27] + "..."
        ultima = f"{d['ultima_duracao']}s" if d["ultima_duracao"] is not None else "-"
        print(f"{nome:<8} {status:<30} {d['chamadas']:>8} {d['tempo_total']:>10.1f}s {ultima:>8} {d['erros']:>6}")

    print(f"\n{'MODELO':<8} {'CHAMADAS':>8} {'TOKENS (entrada)':>17} {'TOKENS (saída)':>15} {'TOKENS (total)':>15}")
    for nome in ("gemini", "claude", "codex"):
        t = tokens_por_modelo.get(nome, {"total": 0, "in": 0, "out": 0, "chamadas": 0})
        print(f"{nome:<8} {t['chamadas']:>8} {t['in']:>17,} {t['out']:>15,} {t['total']:>15,}".replace(",", "."))

    print(f"\n{'FASE':<6} {'PAPEL':<22} {'MODELO':<8} {'STATUS'}")
    fase_atual = None
    for fase, ordem, papel, modelo, modo in roster:
        if fase != fase_atual:
            fase_atual = fase
        chave = (fase, ordem)
        st = estado.get(chave, "pendente")
        if st == "rodando" and chave in inicio_em:
            dt = (agora() - parse_ts(inicio_em[chave])).total_seconds()
            st_txt = f"rodando ({dt:.0f}s)"
        elif chave in duracao and duracao[chave] is not None:
            st_txt = f"{st} ({duracao[chave]}s)"
        else:
            st_txt = st
        print(f"{fase}.{ordem:<4} {papel:<22} {modelo:<8} {st_txt}")

    if not roster:
        print("(equipes/equipes.tsv não encontrado ou vazio)")

if __name__ == "__main__":
    main()
