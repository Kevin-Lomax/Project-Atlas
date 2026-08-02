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

## Fase 3 — MofoMusic Pipeline

**Status: concluída e validada em produção**

- Sprint 1 — `01 - Detector de Vídeos` (Drive → PostgreSQL → Fila).
- Sprint 2 — `02 - Gerador de Legendas` (ffmpeg + Groq Whisper → transcrição e SRT).
- Sprint 3 — `03 - Publicador` (Instagram Reels + Facebook Page → Postados/Erro), 2 publicações por dia.
- Sprint 4 — `04 - Observabilidade` (dashboard, métricas, auto-recuperação, retenção).
- Banco: 6 tabelas do domínio, triggers de auditoria, views e teste automatizado.
- Ver [`docs/ADR/0003-mofomusic-pipeline.md`](ADR/0003-mofomusic-pipeline.md).

Validado end-to-end com vídeo real: detectado no Drive, registrado, transcrito, legendado, publicado no Instagram e no Facebook, arquivado em `/Postados` e refletido no dashboard — sem intervenção manual.

## Fase 4 — Release open source

**Status: concluída — `v1.0.0`**

- Licença MIT.
- Modo de bootstrap do Nginx, para que uma instalação limpa suba antes de existir certificado.
- README com instalação, configuração, operação e troubleshooting.
- Identificadores da instalação original substituídos por placeholders.

## Próximas fases

Ainda não definidas. Fases futuras devem ser aprovadas pelo Arquiteto Principal antes de serem adicionadas a este roadmap.

Candidatos naturais, já suportados pela arquitetura mas **não implementados**: integração das demais redes sociais (TikTok, YouTube Shorts, Threads, X, Pinterest, LinkedIn).
