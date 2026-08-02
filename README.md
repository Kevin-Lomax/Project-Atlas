# Project Atlas

Pipeline de publicação automática de vídeos curtos: detecta vídeos novos no Google Drive, transcreve o áudio, gera legendas e publica no Instagram e Facebook em horários agendados — sem intervenção manual.

Construído sobre Docker Compose, PostgreSQL, n8n e Nginx com TLS, em uma VPS pequena.

```
Google Drive /Entrada
   ↓  detecta (1 min)
PostgreSQL  →  /Fila
   ↓  extrai áudio (ffmpeg) + transcreve (Whisper)
legenda SRT  →  estoque
   ↓  publica 2×/dia (12h e 18h)
Instagram + Facebook  →  /Postados
```

## Stack

| Componente | Papel |
|---|---|
| **PostgreSQL 15** | Estado do pipeline, transcrições, publicações, logs e métricas |
| **n8n** | Orquestração dos 4 workflows |
| **Nginx** | Ingress, terminação TLS, redirect HTTP→HTTPS, mídia temporária |
| **ffmpeg** | Extração de áudio (embutido na imagem do n8n) |
| **Certbot** | Certificado Let's Encrypt e renovação automática (no host) |
| **Fail2Ban / UFW** | Hardening do host |

Decisões e alternativas descartadas em [`docs/ADR/`](docs/ADR/). Visão completa em [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

# Instalação

## Requisitos

- Uma VM ou servidor com **Docker** e **Docker Compose v2**
- Um **domínio** apontando para o IP do servidor (DuckDNS serve bem, é gratuito)
- Portas **80** e **443** liberadas — tanto no firewall do sistema quanto no do provedor de nuvem
- ~1 GB de RAM é suficiente (o projeto roda em VM desse porte)

## 1. Clonar e configurar

```bash
git clone https://github.com/<seu-usuario>/Project-Atlas.git
cd Project-Atlas
cp .env.example .env
```

Edite o `.env`:

- `POSTGRES_PASSWORD` — defina uma senha forte
- `N8N_HOST`, `N8N_WEBHOOK_URL`, `N8N_EDITOR_BASE_URL` — seu domínio
- Deixe `NGINX_CONF=default.bootstrap.conf` por enquanto (ver passo 2)

Troque também o domínio em `ingress/nginx/default.conf` (3 ocorrências de `SEU-DOMINIO.duckdns.org`).

## 2. Bootstrap do SSL

> **Por que este passo existe.** A configuração de produção do Nginx declara `listen 443 ssl` apontando para o certificado do Let's Encrypt. Se o certificado ainda não existe, **o Nginx não inicia** (`cannot load certificate`). Mas o certificado só pode ser emitido com o Nginx já respondendo na porta 80, para servir o desafio ACME. Sem o modo bootstrap, a primeira instalação trava nesse impasse.

Com `NGINX_CONF=default.bootstrap.conf` no `.env`, suba os serviços em modo HTTP:

```bash
docker compose up -d
```

Verifique que o n8n responde: `http://seu-dominio/`

Emita o certificado (o Certbot roda no host, não em container):

```bash
sudo apt-get install -y certbot
sudo certbot certonly --webroot \
  -w "$(pwd)/ingress/certbot/www" \
  -d seu-dominio.duckdns.org \
  --email seu@email.com --agree-tos --non-interactive
```

Configure o recarregamento automático do Nginx após cada renovação:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
echo '#!/bin/bash
docker exec project-atlas-nginx-1 nginx -s reload' \
  | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo certbot renew --dry-run
```

## 3. Ativar HTTPS

Troque no `.env`:

```
NGINX_CONF=default.conf
```

E atualize as URLs para `https://`. Então:

```bash
docker compose up -d
```

Confirme: `https://seu-dominio/` deve responder, e `http://` deve redirecionar (301).

## 4. Criar o banco do pipeline

O n8n cria as próprias tabelas sozinho no primeiro boot, mas **as tabelas do pipeline são criadas por migrations, que não rodam automaticamente**. Aplique na ordem:

```bash
docker exec -i project-atlas-postgres-1 psql -U n8n_user -d n8n -v ON_ERROR_STOP=1 \
  < db/migrations/001_pipeline_schema.sql

docker exec -i project-atlas-postgres-1 psql -U n8n_user -d n8n -v ON_ERROR_STOP=1 \
  < db/migrations/002_observabilidade.sql
```

As migrations são **idempotentes** — rodar de novo não quebra nada e não duplica dados.

Verifique:

```bash
docker exec -i project-atlas-postgres-1 psql -U n8n_user -d n8n -c 'select * from vw_health;'
```

Opcional, mas recomendado — a suíte de testes roda em transação e faz rollback, sem sujar o banco:

```bash
docker exec -i project-atlas-postgres-1 psql -U n8n_user -d n8n -v ON_ERROR_STOP=1 \
  < db/tests/test_pipeline.sql
```

## 5. Criar a conta do n8n

Acesse `https://seu-dominio/` e **crie a conta de owner imediatamente**.

> Enquanto essa conta não existe, a tela de setup fica aberta para qualquer pessoa na internet — quem chegar primeiro vira dono da instância.

---

# Configuração

## Google Drive

1. No **Google Cloud Console**: crie um projeto e ative a **Google Drive API**
2. Crie uma credencial **OAuth 2.0 Client ID** do tipo *Web application*
3. Em *Authorized redirect URIs*, adicione:
   `https://seu-dominio/rest/oauth2-credential/callback`
4. No n8n: **Credentials → Google Drive OAuth2 API** → cole Client ID e Secret → **Sign in with Google**

> Confirme que a autorização realmente completou. Uma credencial só com Client ID e Secret, **sem token de acesso**, falha depois com erros confusos.

Crie no seu Drive quatro pastas — `Entrada`, `Fila`, `Postados`, `Erro` — e anote o ID de cada uma (aparece na URL: `drive.google.com/drive/folders/<ID>`).

## Groq (transcrição)

1. Obtenha uma API key em `console.groq.com`
2. No n8n: **Credentials → Header Auth**
   - Name: `Authorization`
   - Value: `Bearer sua-chave-aqui` ← **com** o prefixo `Bearer`

## Meta (Instagram + Facebook)

Pré-requisitos:

- Conta do Instagram em modo **Profissional** (Business ou Creator)
- **Vinculada** a uma Página do Facebook
- App na Meta com as permissões: `instagram_content_publish`, `instagram_basic`, `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`

Obtenha um **Page access token** e anote o **Instagram Business Account ID** e o **Facebook Page ID**.

> **Prefira um token que não expira.** Um Page token estendido diretamente dura ~60 dias. Para um permanente: obtenha um *user token* de longa duração e então chame `GET /me/accounts` — os Page tokens retornados não expiram.

No n8n: **Credentials → Query Auth**
- Name: `access_token`
- Value: o token puro ← **sem** `Bearer`

## n8n — importar os workflows

```bash
for f in workflows/*.json; do
  docker cp "$f" project-atlas-n8n-1:/tmp/w.json
  docker exec project-atlas-n8n-1 n8n import:workflow --input=/tmp/w.json
done
```

### Depois de importar — passo obrigatório

Os arquivos JSON referenciam **IDs de credencial da instalação original**, que não existem na sua. Em cada workflow você precisa:

1. **Revisar as credenciais**: abra cada node com ícone de credencial (Postgres, Google Drive, HTTP Request) e **selecione a sua** no lugar da que aparece quebrada
2. **Configurar os IDs das pastas** — Workflow 01, node `Config - Pastas do Drive`: `entradaFolderId` e `filaFolderId`
3. **Configurar Meta e demais pastas** — Workflow 03, node `Config - Publicacao`: `igUserId`, `fbPageId`, `postadosFolderId`, `erroFolderId` e `mediaBaseUrl` (com seu domínio)
4. **Salvar** cada workflow
5. **Ativar** os workflows

> É esperado que os nodes apareçam com credencial inválida logo após a importação. IDs de credencial são internos de cada instância do n8n — não há como versioná-los de forma portável.

---

# Operação

## Fila e estoque

A fila **é a própria tabela `videos`** — não existe tabela de fila separada. Cada workflow consome o estado que lhe compete:

```
PENDING → TRANSCRIBING → TRANSCRIBED → PUBLISHING → PUBLISHED
                                                  ↘ PARTIAL
   ↘ ERROR (de qualquer etapa)
```

Produção e distribuição são **desacopladas**: a transcrição processa 1 vídeo a cada 2 minutos, enquanto a publicação sai 2×/dia. Na prática, você pode jogar 50 vídeos na pasta `Entrada` de uma vez — em pouco mais de uma hora todos viram estoque transcrito, e a publicação drena esse estoque ao longo de semanas.

## Agendamento

O Workflow 03 dispara às **12:00 e 18:00** (fuso definido em `GENERIC_TIMEZONE`) e publica **1 vídeo por disparo**.

Para mudar o ritmo, edite o gatilho `Gatilho - 12h e 18h` no editor do n8n: acrescente horários para publicar mais vezes, remova para publicar menos. Nenhuma mudança de banco ou código é necessária.

## Publicação

A cada disparo, o vídeo mais antigo em `TRANSCRIBED` é publicado no Instagram (Reels) e no Facebook (Page), e então movido no Drive para `Postados` — ou para `Erro`, se falhar.

> A Meta **não aceita upload direto** de vídeo neste fluxo: ela exige uma URL de onde baixar o arquivo. Por isso o vídeo é gravado temporariamente em `/media`, servido pelo Nginx sob HTTPS com nome aleatório, e **apagado logo após a publicação**. O diretório não permite listagem, e o Workflow 04 remove órfãos a cada 15 minutos.

## Monitoramento

Dashboard: `https://seu-dominio/webhook/dashboard` (requer o Workflow 04 ativo)

Mostra o estado de cada etapa, publicações por rede, últimos vídeos e erros recentes.

Consultas úteis:

```sql
SELECT * FROM vw_health;                 -- visão consolidada
SELECT * FROM vw_videos_detalhado;       -- vídeo + transcrição + publicações
SELECT * FROM vw_publicacoes_por_rede;   -- desempenho por rede
SELECT * FROM pipeline_logs ORDER BY id DESC LIMIT 20;
```

## Auto-recuperação

Vídeo parado em estado transitório (`TRANSCRIBING`/`PUBLISHING`) por mais de 1 hora indica execução interrompida. O Workflow 04 devolve o vídeo ao estado anterior automaticamente, e ele é reprocessado sem intervenção.

Vídeos em `ERROR` **não** são reprocessados sozinhos — isso é proposital, para não gerar laço infinito. Para liberá-los depois de corrigir a causa:

```sql
UPDATE videos SET status='PENDING', error_message=NULL, retry_count=0 WHERE status='ERROR';
```

## Expandir para outras redes

`TikTok`, `YouTube Shorts`, `Threads`, `X`, `Pinterest` e `LinkedIn` já estão cadastrados em `social_networks` como **desabilitados**. A arquitetura os suporta — o status final é derivado das redes habilitadas. Para ativar uma: habilite a linha e acrescente o ramo de publicação no Workflow 03. Nenhuma mudança de schema é necessária.

---

# Troubleshooting

Problemas reais encontrados durante a construção deste projeto, com a causa e a solução.

### Credencial "inválida" com uma chave que está correta

**Sintoma:** `401 Invalid API Key`, mesmo com a chave certa.

**Causa:** o valor no campo começa com `=`. No n8n, isso significa "trate como *expressão*", não como texto literal.

**Solução:** remova o `=`. Se o campo estiver em modo *Expression* na interface, mude para *Fixed*.

### `Bearer` — quando usar

| Serviço | Tipo | Formato |
|---|---|---|
| Groq | Header Auth | `Bearer sua-chave` — **com** prefixo |
| Meta | Query Auth | `seu-token` — **sem** prefixo |

### Instagram retorna erro de permissão ou não encontra a conta

**Causa provável:** host errado. A Meta tem duas variantes de API:

| Variante | Host | Token |
|---|---|---|
| Instagram API with **Instagram** Login | `graph.instagram.com` | token de usuário do Instagram |
| Instagram API with **Facebook** Login | `graph.facebook.com` | **Page access token** |

**Se você publica também na Página do Facebook**, use a segunda: `igHost = https://graph.facebook.com`.

Para confirmar a que seu token pertence:

```bash
curl -G 'https://graph.facebook.com/v25.0/debug_token' \
  --data-urlencode "input_token=SEU_TOKEN" \
  --data-urlencode "access_token=SEU_TOKEN"
```

`"type":"PAGE"` confirma Page token.

### Nginx não inicia: `cannot load certificate`

**Causa:** configuração de produção sem o certificado emitido.

**Solução:** use `NGINX_CONF=default.bootstrap.conf`, emita o certificado, então volte para `default.conf`. Ver *Instalação → passo 2*.

### 502 Bad Gateway depois de reiniciar o n8n

**Causa:** o Nginx resolve o nome do upstream uma única vez, na inicialização, e guarda o IP. O container do n8n muda de IP a cada recriação.

**Solução:** já corrigida na configuração deste repositório, via `resolver 127.0.0.11` e variável no `proxy_pass`. Se ainda ocorrer: `docker exec project-atlas-nginx-1 nginx -s reload`.

### Workflows não ativam: `Unrecognized node type: n8n-nodes-base.executeCommand`

**Causa:** o n8n 2.0 desabilita `ExecuteCommand` e `LocalFileTrigger` por padrão, por segurança.

**Solução:** `NODES_EXCLUDE=[]` no `.env`. É requisito para o ffmpeg funcionar.

### `Access to the file is not allowed.`

**Causa:** o n8n restringe o acesso ao filesystem (padrão: `~/.n8n-files`).

**Solução:** `N8N_RESTRICT_FILE_ACCESS_TO=/tmp;/media` no `.env`. **O separador é ponto e vírgula**, não dois-pontos.

### Node do tipo Code perde o arquivo de vídeo

**Sintoma:** `This operation expects the node's input data to contain a binary file`.

**Causa:** um Code node que retorna apenas `json` **descarta os dados binários** do item.

**Solução:** repasse explicitamente:

```javascript
return {
  json: { ... },
  binary: $input.item.binary,
};
```

### VM cai ou perde conexão com o banco durante o processamento

**Causa:** vídeos processados em paralelo. Cada um envolve download + gravação em disco + ffmpeg; em VM pequena isso esgota a memória.

**Solução:** `N8N_CONCURRENCY_PRODUCTION_LIMIT=1` no `.env`, e manter `LIMIT 1` nas queries que selecionam vídeos.

---

## Estrutura do projeto

```
Project-Atlas/
├── LICENSE
├── docker-compose.yml
├── .env.example
├── docker/
│   └── n8n/
│       └── Dockerfile                # imagem oficial do n8n + ffmpeg
├── ingress/
│   ├── nginx/
│   │   ├── default.conf              # produção: 80→443, proxy HTTPS, /media
│   │   └── default.bootstrap.conf    # primeira instalação: só HTTP
│   └── certbot/
│       └── www/                      # webroot do desafio HTTP-01
├── db/
│   ├── migrations/                   # schema do pipeline (idempotente)
│   └── tests/                        # teste automatizado do pipeline
├── workflows/                        # os 4 workflows do n8n em JSON
└── docs/
    ├── ARCHITECTURE.md
    ├── ROADMAP.md
    └── ADR/                          # decisões arquiteturais
```

Persistência via volumes Docker nomeados (`postgres_data`, `n8n_data`, `media_data`). O certificado TLS fica em `/etc/letsencrypt` no host, fora do repositório.

## Backup

Não incluso no repositório por depender do host, mas recomendado: dump do PostgreSQL, export dos workflows e cópia do volume do n8n, agendados via cron. Na instalação de referência isso roda diariamente às 03:00, mantendo os 7 backups mais recentes.

## Licença

[MIT](LICENSE) — uso, modificação e distribuição livres, inclusive comercialmente.
