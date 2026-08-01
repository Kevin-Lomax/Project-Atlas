# Project Atlas

Infraestrutura de produção baseada em Docker Compose, com PostgreSQL, n8n e Nginx (TLS via Let's Encrypt), além de hardening de VM (SSH, UFW, Fail2Ban) e backup automatizado.

## Stack

- **PostgreSQL 15** — banco de dados.
- **n8n** — automação de workflows.
- **Nginx** — camada de ingress, com terminação TLS (Let's Encrypt/Certbot) e redirect HTTP→HTTPS.
- **Certbot** — emissão e renovação automática do certificado (roda no host da VM, fora do Docker Compose).
- **Fail2Ban** — proteção do SSH contra força bruta (roda no host da VM).

Ver detalhes e justificativa em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) e nas decisões registradas em [`docs/ADR/`](docs/ADR/).

## Como executar

1. Copie o arquivo de exemplo de variáveis de ambiente:
   ```
   cp .env.example .env
   ```
2. Edite o `.env` com suas credenciais reais e o domínio configurado.
3. Suba os serviços:
   ```
   docker compose up -d
   ```
4. Na primeira emissão do certificado, veja o passo a passo em
   [`docs/ADR/0002-https-e-hardening.md`](docs/ADR/0002-https-e-hardening.md)
   (requer o domínio já apontando para o IP do servidor).

## Estrutura do projeto

```
Project-Atlas/
├── docker-compose.yml
├── .env.example
├── ingress/
│   ├── nginx/
│   │   └── default.conf   # Nginx: redirect 80→443 + proxy reverso HTTPS para o n8n
│   └── certbot/
│       └── www/            # webroot usado no desafio HTTP-01 do Let's Encrypt
├── workflows/              # reservado para workflows do n8n
└── docs/
    ├── ARCHITECTURE.md
    ├── ROADMAP.md
    └── ADR/                # registro de decisões arquiteturais
```

A persistência do PostgreSQL e do n8n é feita via volumes Docker nomeados (`postgres_data`, `n8n_data`), gerenciados pelo próprio Docker — não há diretórios locais de dados no projeto. O certificado TLS fica em `/etc/letsencrypt` no host da VM (fora do repositório).

## Operação

- **Backup**: script `/opt/backups/backup.sh` na VM (fora do repositório), agendado via cron diariamente às 03:00. Faz dump do PostgreSQL, export dos workflows e cópia do volume `n8n_data`, compactando tudo e mantendo apenas os 7 backups mais recentes.
- **Renovação de certificado**: automática via timer do `certbot` no host, com hook que recarrega o Nginx do Docker após cada renovação.

## Governança

Este projeto segue as diretrizes definidas em [`CLAUDE.md`](CLAUDE.md): decisões arquiteturais são de responsabilidade do Arquiteto Principal, e o Claude Code atua como implementador do escopo já aprovado.
