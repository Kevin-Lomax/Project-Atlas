# Imagem do n8n com ffmpeg.
#
# O ffmpeg é necessário no Workflow 02 (Gerador de Legendas) para extrair
# apenas a trilha de áudio do vídeo antes de enviá-la à API de transcrição:
# um vídeo de ~100 MB vira um mp3 de poucos MB, ficando com folga dentro do
# limite de upload da API e reduzindo drasticamente o tempo de envio.
#
# A imagem oficial do n8n é uma "Docker Hardened Image" (Alpine sem
# gerenciador de pacotes e sem utilitários de build), então:
#
#   1. não é possível instalar nada com `apk` nela;
#   2. não é possível sequer rodar `RUN` com printf/chmod nela.
#
# Por isso tudo é preparado num estágio Alpine limpo da MESMA versão (ABI
# musl compatível) e apenas COPIADO para a imagem final. As bibliotecas do
# ffmpeg ficam em /opt/ffmpeg/lib — diretório isolado que NÃO sobrescreve
# nenhuma biblioteca do sistema — e o LD_LIBRARY_PATH é aplicado somente
# dentro do wrapper do ffmpeg, nunca como variável global da imagem, para
# que o processo do Node/n8n continue resolvendo suas próprias bibliotecas.

ARG N8N_VERSION=2.32.1

FROM alpine:3.24 AS ffmpeg-src
RUN apk add --no-cache ffmpeg \
 && printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/ffmpeg/lib:/opt/ffmpeg/lib/pulseaudio exec /opt/ffmpeg/bin/ffmpeg "$@"\n'  > /wrappers-ffmpeg \
 && printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/ffmpeg/lib:/opt/ffmpeg/lib/pulseaudio exec /opt/ffmpeg/bin/ffprobe "$@"\n' > /wrappers-ffprobe \
 && chmod +x /wrappers-ffmpeg /wrappers-ffprobe

FROM n8nio/n8n:${N8N_VERSION}

COPY --from=ffmpeg-src /usr/bin/ffmpeg      /opt/ffmpeg/bin/ffmpeg
COPY --from=ffmpeg-src /usr/bin/ffprobe     /opt/ffmpeg/bin/ffprobe
COPY --from=ffmpeg-src /usr/lib/            /opt/ffmpeg/lib/
COPY --from=ffmpeg-src /wrappers-ffmpeg     /usr/local/bin/ffmpeg
COPY --from=ffmpeg-src /wrappers-ffprobe    /usr/local/bin/ffprobe
