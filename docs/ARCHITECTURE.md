# Arquitetura — Project Atlas

## Visão geral

O Project Atlas é composto por três serviços orquestrados via Docker Compose, conectados por uma única rede bridge (`app-network`).

## Serviços

### PostgreSQL

- Imagem: `postgres:15-alpine`.
- Persistência: volume local `./db/data`.
- Configuração via variáveis de ambiente em `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).

### n8n

- Imagem: `n8nio/n8n:2.32.1`.
- Persistência: volume nomeado `n8n_data`.
- Autenticação básica habilitada via variáveis de ambiente (`N8N_BASIC_AUTH_*`).
- Não exposto diretamente para fora da rede interna — acesso previsto via Nginx.

### Nginx

- Imagem: `nginx:alpine`.
- Porta `80` exposta ao host.
- Atua como camada de ingress. Configuração customizada ainda não implementada — hoje o serviço roda com a configuração padrão da imagem.

## Rede

Um único network bridge (`app-network`) conecta os três serviços. Não há segmentação adicional de rede neste estágio.

## Diretórios reservados

- `ingress/` — reservado para arquivos de configuração do Nginx (ainda não conectado ao serviço via volume).
- `workflows/` — reservado para definições de workflows do n8n.

## Restrições arquiteturais

Conforme definido em [`CLAUDE.md`](../CLAUDE.md), este projeto não deve incorporar componentes adicionais (Prometheus, Grafana, Kubernetes, Traefik, GitHub Actions, AWS, GCP, Redis, RabbitMQ, balanceadores, serviços extras) sem aprovação explícita do Arquiteto Principal.
