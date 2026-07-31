# Project Atlas

Infraestrutura inicial baseada em Docker Compose, com PostgreSQL, n8n e Nginx.

## Stack

- **PostgreSQL 15** — banco de dados.
- **n8n** — automação de workflows.
- **Nginx** — camada de ingress.

Ver detalhes e justificativa em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) e nas decisões registradas em [`docs/ADR/`](docs/ADR/).

## Como executar

1. Copie o arquivo de exemplo de variáveis de ambiente:
   ```
   cp .env.example .env
   ```
2. Edite o `.env` com suas credenciais reais.
3. Suba os serviços:
   ```
   docker compose up -d
   ```

## Estrutura do projeto

```
Project-Atlas/
├── docker-compose.yml
├── .env.example
├── db/               # volume de dados do PostgreSQL
├── ingress/          # reservado para configuração do Nginx
├── workflows/         # reservado para workflows do n8n
└── docs/
    ├── ARCHITECTURE.md
    ├── ROADMAP.md
    └── ADR/           # registro de decisões arquiteturais
```

## Governança

Este projeto segue as diretrizes definidas em [`CLAUDE.md`](CLAUDE.md): decisões arquiteturais são de responsabilidade do Arquiteto Principal, e o Claude Code atua como implementador do escopo já aprovado.
