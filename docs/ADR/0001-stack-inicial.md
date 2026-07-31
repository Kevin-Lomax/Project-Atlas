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
