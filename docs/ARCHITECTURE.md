# Arquitetura — Project Atlas

## Visão geral

O Project Atlas é composto por três serviços orquestrados via Docker Compose, conectados por uma única rede bridge (`app-network`).

## Serviços

### PostgreSQL

- Imagem: `postgres:15-alpine`.
- Persistência: volume Docker nomeado `postgres_data`, gerenciado pelo próprio Docker.
- Configuração via variáveis de ambiente em `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).

### n8n

- Imagem: `n8nio/n8n:2.32.1`.
- Persistência: volume nomeado `n8n_data`.
- Autenticação básica habilitada via variáveis de ambiente (`N8N_BASIC_AUTH_*`).
- Não exposto diretamente para fora da rede interna — a única porta publicada ao host é a `80`, do Nginx.

### Nginx

- Imagem: `nginx:stable-alpine`.
- Porta `80` exposta ao host.
- Atua como camada de ingress: reverse proxy para o n8n (`ingress/nginx/default.conf`), incluindo suporte a WebSocket (necessário para a interface do n8n).
- Sem terminação TLS/HTTPS implementada nesta camada — o serviço atende apenas HTTP na porta 80.

## Rede

Um único network bridge (`app-network`) conecta os três serviços. Não há segmentação adicional de rede neste estágio.

## Diretórios reservados

- `ingress/nginx/` — contém a configuração do Nginx, conectada ao serviço via bind mount somente leitura.
- `workflows/` — reservado para definições de workflows do n8n (ainda não utilizado).

## Restrições arquiteturais

Conforme definido em [`CLAUDE.md`](../CLAUDE.md), este projeto não deve incorporar componentes adicionais (Prometheus, Grafana, Kubernetes, Traefik, GitHub Actions, AWS, GCP, Redis, RabbitMQ, balanceadores, serviços extras) sem aprovação explícita do Arquiteto Principal.
