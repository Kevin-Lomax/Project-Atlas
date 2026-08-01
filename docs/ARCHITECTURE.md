# Arquitetura — Project Atlas

## Visão geral

O Project Atlas é composto por três serviços orquestrados via Docker Compose, conectados por uma única rede bridge (`app-network`), mais duas camadas de segurança/operação que rodam diretamente no host da VM (fora do Docker Compose): Certbot (TLS) e Fail2Ban (proteção do SSH).

## Serviços (Docker Compose)

### PostgreSQL

- Imagem: `postgres:15-alpine`.
- Persistência: volume Docker nomeado `postgres_data`, gerenciado pelo próprio Docker.
- Configuração via variáveis de ambiente em `.env` (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).
- Healthcheck via `pg_isready`.

### n8n

- Imagem: `n8nio/n8n:2.32.1`.
- Persistência: volume nomeado `n8n_data`.
- Autenticação feita pelo sistema de usuários próprio do n8n (conta de owner criada na primeira execução via `/setup`) — as antigas variáveis `N8N_BASIC_AUTH_*` foram removidas por estarem depreciadas e sem efeito.
- Não exposto diretamente para fora da rede interna — a única forma de acesso externo é via Nginx.
- Healthcheck via `/healthz`; o Nginx só inicia depois que o n8n reporta saudável (`depends_on: condition: service_healthy`).

### Nginx

- Imagem: `nginx:1.30-alpine` (pinada, alinhada com a versão em produção).
- Portas `80` e `443` expostas ao host.
- Porta 80: só responde ao desafio ACME (`/.well-known/acme-challenge/`) do Let's Encrypt e redireciona (301) todo o resto para HTTPS.
- Porta 443: termina TLS (certificado emitido pelo Certbot) e faz proxy reverso para o n8n, incluindo suporte a WebSocket (necessário para a interface do n8n) e timeouts de proxy estendidos (300s) para acomodar execuções longas de workflow via webhook.
- Envia `Strict-Transport-Security` e restringe a `TLSv1.2`/`TLSv1.3`.
- Healthcheck próprio (`wget` contra `https://127.0.0.1` internamente).

## Camada de segurança e TLS (host da VM, fora do Docker Compose)

### Certbot

- Instalado via `apt` diretamente no host (não é um container).
- Certificado emitido por webroot (`ingress/certbot/www`, montado no Nginx), evitando downtime durante a emissão.
- Renovação automática via timer do systemd (`certbot.timer`), com hook em `/etc/letsencrypt/renewal-hooks/deploy/` que recarrega o Nginx do Docker (`nginx -s reload`) após cada renovação.
- Os arquivos do certificado (`/etc/letsencrypt`) são montados como bind mount somente leitura no container do Nginx.

### Fail2Ban

- Instalado via `apt` no host. Jail `sshd` habilitada: 5 tentativas em 10 minutos, ban de 1 hora.

### UFW (firewall)

- Libera apenas `22/tcp`, `80/tcp` e `443/tcp` (v4 e v6); nega o resto por padrão.

### SSH

- Login por senha desabilitado (`PasswordAuthentication no`), root só via chave (`PermitRootLogin without-password`).

## Backup

- Script `/opt/backups/backup.sh` no host (fora do repositório), agendado via cron diariamente às 03:00.
- Faz dump do PostgreSQL, export dos workflows (`n8n export:workflow`) e cópia do volume `n8n_data`, compactando tudo em um `.tar.gz` por execução.
- Retenção automática: mantém apenas os 7 backups mais recentes.

## MofoMusic Pipeline (workflows do n8n)

O produto que roda sobre esta infraestrutura. Detalhes e justificativas em [`ADR/0003-mofomusic-pipeline.md`](ADR/0003-mofomusic-pipeline.md).

```
Google Drive /Entrada
        │  (Cron 1 min)
        ▼
01 - Detector de Vídeos ──── registra em videos (PENDING) ── move → /Fila
        │
        ▼
02 - Gerador de Legendas ─── baixa · ffmpeg extrai áudio · Groq transcreve
        │                    grava transcrição + SRT (TRANSCRIBED)
        ▼
03 - Publicador ──────────── Instagram (Reels) + Facebook (Page)
        │                    move → /Postados  ou  → /Erro
        ▼
04 - Observabilidade ─────── dashboard · métricas · auto-recuperação · retenção
```

Os workflows **não se chamam em cadeia**: cada um consome o estado que lhe compete em `videos.status`. Isso permite que qualquer etapa falhe ou seja reprocessada isoladamente.

Ciclo de vida de um vídeo:

```
PENDING → TRANSCRIBING → TRANSCRIBED → PUBLISHING → PUBLISHED
                                                  ↘ PARTIAL
   ↘ ERROR (a partir de qualquer etapa)
```

### Banco de dados do pipeline

| Tabela | Papel |
|---|---|
| `videos` | Registro central e estado de cada vídeo |
| `video_transcriptions` | Transcrição e legenda SRT (1:1 com vídeo) |
| `social_networks` | Catálogo das redes; `enabled` controla quais são publicadas |
| `video_publications` | Uma linha por (vídeo, rede), com id do post e erro |
| `video_status_history` | Auditoria automática de transições (via trigger) |
| `pipeline_logs` | Log estruturado dos workflows, com retenção de 30 dias |
| `pipeline_metrics` | Snapshots periódicos para série histórica |

Views de apoio: `vw_health`, `vw_pipeline_status`, `vw_videos_detalhado`, `vw_publicacoes_por_rede`.

Migrations idempotentes em `db/migrations/`; teste automatizado do pipeline em `db/tests/test_pipeline.sql`.

### Área pública temporária de mídia

A Meta Graph API exige uma URL pública de onde baixar o vídeo. O Workflow 03 grava o arquivo no volume `media_data` (servido pelo Nginx em `/media/` sob HTTPS) com nome aleatório, publica e apaga em seguida. `autoindex` está desligado e o Workflow 04 remove órfãos a cada 15 minutos.

### Expansão para outras redes

TikTok, YouTube Shorts, Threads, X, Pinterest e LinkedIn já estão cadastrados em `social_networks` como **desabilitados**. A arquitetura os suporta (o status final é derivado das redes habilitadas); falta apenas a integração de cada um, que é trabalho futuro e não faz parte do escopo atual.

## Rede

Um único network bridge (`app-network`) conecta os três serviços do Docker Compose. Não há segmentação adicional de rede neste estágio.

## Diretórios reservados

- `ingress/nginx/` — contém a configuração do Nginx, conectada ao serviço via bind mount somente leitura.
- `ingress/certbot/www/` — webroot usado no desafio HTTP-01 do Let's Encrypt.
- `workflows/` — reservado para definições de workflows do n8n (ainda não utilizado).

## Restrições arquiteturais

Conforme definido em [`CLAUDE.md`](../CLAUDE.md), este projeto não deve incorporar componentes adicionais (Prometheus, Grafana, Kubernetes, Traefik, GitHub Actions, AWS, GCP, Redis, RabbitMQ, balanceadores, serviços extras) sem aprovação explícita do Arquiteto Principal.
