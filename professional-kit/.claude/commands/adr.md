---
description: Cria um novo ADR a partir do template, sem inventar conteúdo de decisão
argument-hint: [título da decisão]
---

Crie um novo ADR (Architecture Decision Record) para: $ARGUMENTS

Se nenhum título for informado, peça ao usuário para especificar o título da decisão antes de prosseguir.

Passos:

1. Use `docs/ADR/template.md` deste projeto como base. Não modifique o template — apenas leia-o para gerar a cópia.
2. Verifique os arquivos existentes em `docs/ADR/` para determinar o próximo número sequencial (formato `NNNN`, começando em `0001`).
3. Crie o novo arquivo em `docs/ADR/NNNN-titulo-da-decisao.md`, com o título convertido para kebab-case.
4. Preencha apenas os campos objetivos do template:
   - `{{NUMERO}}` → número sequencial determinado no passo 2.
   - `{{TITULO}}` → título informado em `$ARGUMENTS`.
   - `{{AAAA-MM-DD}}` → data atual.
   - `Status` → `Proposto`, a menos que o usuário informe outro status.
5. Nunca invente conteúdo para as seções Contexto, Decisão, Alternativas consideradas ou Consequências. Preencha essas seções somente com informações explicitamente fornecidas pelo usuário nesta solicitação; caso contrário, mantenha os placeholders originais do template.

Regras:
- Não altere `docs/ADR/template.md`.
- Não crie mais de um arquivo por execução.
- Ao final, informe o caminho do arquivo criado e aguarde revisão do usuário.
