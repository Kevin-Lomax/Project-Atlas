# ADR 0003: Arquitetura do MofoMusic Pipeline

## Status

Aprovado

## Data

2026-08-01

## Contexto

Com a infraestrutura concluída (ADR 0001 e 0002), o projeto passou a implementar o produto: um pipeline que detecta vídeos no Google Drive, gera legendas por transcrição e publica em redes sociais, com previsão de expansão para outras redes no futuro.

## Decisão

### Divisão em quatro workflows

O pipeline foi dividido em quatro workflows independentes, comunicando-se pelo banco de dados:

| Workflow | Responsabilidade | Gatilho |
|---|---|---|
| `01 - Detector de Vídeos` | Detecta vídeos novos, registra e move para Fila | Cron 1 min |
| `02 - Gerador de Legendas` | Extrai áudio, transcreve e gera SRT | Chamado pelo 01 |
| `03 - Publicador` | Publica no Instagram/Facebook, move para Postados ou Erro | Cron 12:00 e 18:00 |
| `04 - Observabilidade` | Dashboard, métricas, auto-recuperação e retenção | Cron 15 min + Webhook |

O acoplamento é feito por **estado no banco** (`videos.status`), não por chamadas encadeadas. Cada workflow pega o que está no estado que lhe compete. Isso significa que qualquer etapa pode falhar, ser reprocessada ou rodar em ritmo diferente sem quebrar as demais.

Consequência prática importante: **produção e distribuição rodam em ritmos independentes**. A transcrição processa 1 vídeo a cada 2 minutos, enquanto a publicação sai 2× por dia. Isso permite transcrever um lote inteiro de uma vez e deixá-lo como estoque, drenado aos poucos pela publicação — sem nenhuma fila ou agendador adicional, apenas pelo estado no banco.

O Workflow 01 chama o 02 diretamente (sem esperar retorno) apenas para reduzir latência; se essa chamada falhar, o vídeo continua em `PENDING` e seria reprocessado de qualquer forma.

### Estado como fonte da verdade

```
PENDING → TRANSCRIBING → TRANSCRIBED → PUBLISHING → PUBLISHED
                                                  ↘ PARTIAL
   ↘ ERROR (de qualquer etapa)
```

Transições são registradas automaticamente em `video_status_history` por trigger do banco — nenhum workflow precisa lembrar de auditar.

### ffmpeg para extração de áudio

A API de transcrição aceita vídeo, mas tem limite de 25 MB (plano free). Extrair só o áudio (mp3 mono 16 kHz) reduz o arquivo em ~95%, tirando o limite de tamanho do caminho crítico.

A imagem oficial do n8n é uma *Docker Hardened Image* sem gerenciador de pacotes, então o ffmpeg é copiado de um estágio Alpine da mesma versão, com bibliotecas isoladas em `/opt/ffmpeg/lib` e `LD_LIBRARY_PATH` aplicado apenas dentro de um wrapper — o processo do Node continua resolvendo suas próprias bibliotecas normalmente.

### Área pública temporária de mídia

A Meta Graph API não aceita upload direto de vídeo neste fluxo: exige uma URL de onde possa baixar o arquivo. Como o projeto já tem Nginx com TLS válido, o vídeo é gravado em um volume servido em `/media/`, publicado e **apagado em seguida**.

Mitigações: nome de arquivo aleatório (32 caracteres), `autoindex off`, `Cache-Control: no-store`, remoção imediata após publicação e uma limpeza de órfãos a cada 15 minutos no Workflow 04.

### Parâmetros de publicação verificados empiricamente

A Graph API **ignora silenciosamente parâmetros desconhecidos** na criação do container — enviar um campo inexistente devolve sucesso normalmente. Isso significa que "a API aceitou" não prova que o parâmetro existe, e código construído sobre essa suposição vira decoração: parece configurar algo e não configura nada.

O teste que discrimina é enviar um **valor inválido**: se o parâmetro for real, a API valida e rejeita; se não existir, ela ignora.

Resultado para `media_type=REELS` na v25.0:

| Parâmetro | Veredito |
|---|---|
| `share_to_feed` | **existe** — `(#100) Param share_to_feed must be a boolean` |
| `thumb_offset` | **não existe** — ignorado, igual a um campo inventado |

Só `share_to_feed` foi implementado. Ele faz o Reel aparecer também no feed e na grade do perfil, não apenas na aba Reels — mais superfície de exibição pelo mesmo post.

### Catálogo de redes em vez de workflows por rede

`social_networks` cataloga as oito redes previstas; `video_publications` guarda uma linha por (vídeo, rede). Instagram e Facebook estão habilitados; TikTok, YouTube Shorts, Threads, X, Pinterest e LinkedIn estão cadastrados e **desabilitados**.

Consequência prática: uma rede pode falhar sem afetar a outra, o status final é *derivado* das publicações reais, e adicionar uma rede nova é habilitar a linha e acrescentar o ramo — sem tocar no schema nem nos outros workflows.

## Alternativas consideradas

- **Um único workflow monolítico** — descartado: uma falha na publicação obrigaria a refazer a transcrição, e o tempo total de execução ultrapassaria qualquer intervalo de Cron razoável.
- **Fila dedicada (Redis/RabbitMQ)** — descartado: o `CLAUDE.md` proíbe esses componentes sem aprovação, e o PostgreSQL já existente atende o volume esperado com `status` + índice.
- **Tornar o arquivo do Drive público para a Meta baixar** — descartado: o Drive insere página intermediária de verificação em arquivos maiores, o que quebra o download automático, e exigiria afrouxar permissões na conta do usuário.
- **Enviar o vídeo inteiro para transcrição** — descartado: estoura o limite de 25 MB em vídeos de poucos minutos.

## Consequências

- O banco passou de 1 para 6 tabelas do domínio, com triggers, views e função de retenção. Migrations idempotentes ficam em `db/migrations/`.
- A imagem do n8n deixou de ser a oficial pura e passou a ser construída localmente (`docker/n8n/Dockerfile`). Atualizar a versão do n8n agora exige rebuild, não só `docker compose pull`.
- Existe uma janela — de segundos a poucos minutos — em que o vídeo fica publicamente acessível por URL não adivinhável. É uma exigência da API da Meta, não uma escolha de projeto.
- Vídeos presos em estado transitório há mais de 1 hora voltam sozinhos ao estado anterior (Workflow 04). Isso torna o pipeline auto-recuperável, mas significa que uma execução muito longa (>1h) poderia ser reprocessada em duplicidade; o limite foi escolhido bem acima do tempo real esperado por vídeo.
