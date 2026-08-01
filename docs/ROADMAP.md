# Roadmap — Project Atlas

## Fase 1 — Estrutura inicial da infraestrutura

**Status: concluída**

- Definição do `docker-compose.yml` com PostgreSQL, n8n e Nginx.
- Definição do `.env.example`.
- Estrutura de diretórios (`ingress/`, `workflows/`, `docs/`).

## Fase 2 — HTTPS e hardening da VM

**Status: concluída**

- TLS via Nginx + Certbot (Let's Encrypt), com renovação automática.
- Hardening da VM: SSH (chave apenas), UFW, Fail2Ban.
- Backup automatizado com retenção (7 backups) via cron.
- Healthchecks em todos os serviços do Docker Compose.
- Ver [`docs/ADR/0002-https-e-hardening.md`](ADR/0002-https-e-hardening.md).

## Próximas fases

Ainda não definidas. Fases futuras devem ser aprovadas pelo Arquiteto Principal antes de serem adicionadas a este roadmap.
