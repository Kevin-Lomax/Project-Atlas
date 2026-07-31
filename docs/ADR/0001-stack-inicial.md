# ADR 0001: Stack inicial da infraestrutura

## Status

Aprovado

## Data

2026-07-27

## Contexto

O Project Atlas precisava de uma infraestrutura inicial mínima para suportar automação de workflows com persistência de dados e uma camada de ingress, sem incorporar componentes além do estritamente necessário.

## Decisão

Adotar como stack inicial:

- **PostgreSQL 15 (alpine)** como banco de dados.
- **n8n** como motor de automação de workflows.
- **Nginx (alpine)** como camada de ingress.

Os três serviços são orquestrados via Docker Compose, conectados por uma única rede bridge (`app-network`), sem segmentação adicional.

## Alternativas consideradas

Não há registro de alternativas avaliadas para este ADR retroativo. A decisão de stack já estava implementada no momento da criação deste documento (commit "fase 1 - estrutura inicial da infraestrutura").

## Consequências

- A infraestrutura permanece mínima e alinhada às restrições do `CLAUDE.md` (sem Prometheus, Grafana, Kubernetes, Traefik, GitHub Actions, AWS, GCP, Redis, RabbitMQ, balanceadores ou serviços extras).
- Qualquer necessidade futura de observabilidade, escalonamento ou CI/CD exigirá uma nova decisão arquitetural explícita, não coberta por este ADR.
- O Nginx está declarado mas ainda sem configuração customizada — a configuração efetiva do ingress é uma decisão pendente, fora do escopo deste ADR.

## Atualização (2026-07-31)

A configuração de ingress mencionada acima como pendente foi implementada em `ingress/nginx/default.conf` (reverse proxy para o n8n, com suporte a WebSocket). A persistência do PostgreSQL também passou a usar um volume Docker nomeado (`postgres_data`) em vez do bind mount local `./db/data` citado implicitamente no contexto original. Nenhuma das duas mudanças altera a decisão de stack registrada nesta ADR — ambas permanecem dentro do escopo original (PostgreSQL + n8n + Nginx, rede bridge única, sem componentes adicionais). Esta seção é um addendum; o conteúdo original acima foi preservado sem alterações.
