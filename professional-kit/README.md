# Professional Kit

Base reutilizável de configuração para o Claude Code CLI, aplicável a qualquer projeto.

## Conteúdo

- `CLAUDE.md.template` — modelo de governança (papel do Claude Code, hierarquia de decisões, escopo, regras de conduta).
- `.claude/settings.json` — permissões base mínimas para o Claude Code CLI.
- `docs/ADR/template.md` — modelo de Architecture Decision Record.
- `.claude/commands/audit.md` (`/audit`) — gera um relatório de auditoria do projeto (o que existe, o que permanece, o que remover, o que recriar, proposta mínima), sem alterar arquivos.
- `.claude/commands/critical-review.md` (`/critical-review`) — realiza revisão crítica de um ou mais arquivos com 5 critérios fixos (bom, simplificável, específico demais, custo de tokens, ambiguidades), sem alterar arquivos.
- `.claude/commands/adr.md` (`/adr`) — cria um novo ADR a partir do `docs/ADR/template.md`, preenchendo apenas campos objetivos e sem inventar conteúdo de decisão.

## Como usar em um novo projeto

1. Copie `CLAUDE.md.template` para a raiz do novo projeto como `CLAUDE.md` e preencha os campos marcados com `{{DEFINIR: ...}}`.
2. Copie `.claude/settings.json` para `.claude/settings.json` do novo projeto. Este arquivo é apenas um **baseline mínimo** — não é uma configuração completa. Adapte as permissões (`allow`) às necessidades reais de cada projeto (ex.: Bash, Edit, domínios de WebFetch específicos).
3. Copie `docs/ADR/template.md` para `docs/ADR/` do novo projeto. Use uma cópia por decisão registrada (ex.: `docs/ADR/0001-nome-da-decisao.md`).
4. Copie a pasta `.claude/commands/` para `.claude/commands/` do novo projeto, para disponibilizar os comandos `/audit`, `/critical-review` e `/adr`.

## Permissões dos commands

Os commands podem solicitar permissões adicionais na primeira execução (ex.: leitura de arquivos, escrita para `/adr`), dependendo do que já estiver liberado no `.claude/settings.json` do projeto. Como o `settings.json` do kit é apenas um baseline mínimo, é esperado que o Claude Code peça aprovação nessas primeiras execuções até que as permissões necessárias sejam adicionadas.

## `settings.json` vs `settings.local.json`

- `.claude/settings.json` — versionado no repositório, compartilhado por toda a equipe. É este arquivo que o kit fornece.
- `.claude/settings.local.json` — local à máquina do desenvolvedor, normalmente ignorado no `.gitignore`, usado para permissões pessoais que não devem ir para o repositório compartilhado.

Use `settings.json` para as permissões que todo o time deve ter por padrão no projeto. Use `settings.local.json` apenas para ajustes individuais (ex.: uma permissão que só um desenvolvedor específico precisa). Os dois arquivos podem coexistir — o Claude Code combina as permissões de ambos.

## Migração de projetos existentes

Se o projeto de destino já possuir `CLAUDE.md`, `.claude/settings.json` e/ou `.claude/settings.local.json`, **não sobrescreva esses arquivos**. Em vez disso:

- **`CLAUDE.md` existente**: não substitua pelo `CLAUDE.md.template`. Leia os dois lado a lado e incorpore manualmente, na versão existente, apenas as seções do template que ainda não estejam cobertas (ex.: fallback de autoridade, regras gerais). A decisão sobre o que mesclar é do desenvolvedor responsável pelo projeto.
- **`.claude/settings.json` existente**: não substitua pelo do kit. Adicione manualmente ao arquivo existente apenas as permissões do kit que ainda não estiverem presentes.
- **`.claude/settings.local.json` existente**: como este arquivo é local e já cumpre um papel diferente do `settings.json` do kit (ver seção acima), normalmente não precisa de alteração. Revise se alguma permissão dele deveria, na verdade, estar no `settings.json` compartilhado.

Em todos os casos, trate a cópia dos templates do kit como ponto de partida para revisão manual, não como substituição automática. Sempre revise o resultado antes de commitar.

## Escopo desta etapa

Este kit contém templates reutilizáveis (`CLAUDE.md.template`, `.claude/settings.json`, `docs/ADR/template.md`) e os slash commands `/audit`, `/critical-review` e `/adr`. Não inclui agents, skills ou hooks.
