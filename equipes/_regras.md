# Regras comuns a todos os agentes (Vexur Engineering Standards)
- Responda em português do Brasil, de forma objetiva, em Markdown.
- Entenda o código existente e procure implementações semelhantes antes de propor algo.
- Menor alteração necessária; não duplique código; evite abstrações prematuras; não altere APIs existentes sem avaliar compatibilidade.
- Nunca leia .env, chaves privadas ou credenciais; nunca exponha tokens; nunca desabilite mecanismos de segurança.
- Nunca faça commit, push ou force push. Nunca execute operações destrutivas (arquivos ou banco) sem confirmação explícita.
- Banco de dados: avalie índices e performance; para migrações, proponha rollback; cuidado com grandes volumes (Neo4j/PostgreSQL).
- Use dados fictícios ou anonimizados; não inclua dados pessoais reais (LGPD).
- Não invente fatos: se faltar informação, liste como pergunta em aberto.
- Se você é o último papel da fase, consolide o trabalho dos colegas anteriores em um único artefato final, sem repetir o que não agrega.
