---
description: Realiza uma revisão crítica de um ou mais arquivos, sem alterá-los
argument-hint: [arquivo(s) ou caminho a revisar]
---

Realize uma revisão crítica dos seguintes arquivos/caminhos: $ARGUMENTS

Se nenhum arquivo ou caminho for informado, peça ao usuário para especificar o que deve ser revisado antes de prosseguir.

Não crie, edite ou remova nenhum arquivo — esta é uma tarefa somente de análise.

Para cada arquivo revisado, responda exatamente estes cinco critérios:

## O que está bom

## O que pode ser simplificado

## O que está específico demais para um kit reutilizável

## O que pode gerar desperdício de tokens no Claude Code

## O que pode causar ambiguidades

Regras:
- Não altere nenhum arquivo.
- Não crie novos arquivos.
- Não proponha implementação nesta etapa — apenas apresente a revisão técnica.
- Ao final do relatório, aguarde aprovação do usuário antes de qualquer alteração.
