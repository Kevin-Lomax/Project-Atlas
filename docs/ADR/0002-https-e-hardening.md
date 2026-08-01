# ADR 0002: HTTPS via Certbot + hardening da VM

## Status

Aprovado

## Data

2026-08-01

## Contexto

O ADR 0001 deixou explicitamente registrado que TLS/HTTPS não estava implementado e exigiria uma decisão arquitetural própria. Além disso, a VM de produção precisava de um nível básico de segurança operacional (proteção contra força bruta no SSH, firewall, backups) antes de ser considerada pronta para receber workflows reais.

## Decisão

- **TLS/HTTPS**: terminado no Nginx já existente (sem trocar o componente), usando **Certbot** para emitir e renovar certificados Let's Encrypt. O Certbot roda diretamente no host da VM via `apt` — não é um container adicional nem um novo serviço no `docker-compose.yml`. Emissão feita por desafio HTTP-01 via webroot (`ingress/certbot/www`).
- **Fail2Ban**: instalado no host via `apt` para proteger o SSH contra força bruta (jail `sshd`: 5 tentativas / 10 min / ban de 1h).
- **UFW**: libera apenas `22/80/443`, nega o resto.
- **Backup**: script local no host (`/opt/backups/backup.sh`), agendado via cron, sem serviço ou dependência externa nova.

## Alternativas consideradas

- **Traefik** como reverse proxy com TLS automático — descartado por substituir o Nginx já aprovado no ADR 0001 e por estar explicitamente fora da lista de componentes permitidos no `CLAUDE.md` sem aprovação.
- **TLS terminado fora da VM** (ex.: proxy de terceiros na frente do domínio) — descartado por introduzir uma dependência externa fora da arquitetura aprovada.
- **`nginx-proxy` + `acme-companion`** (automação via containers) — descartado por adicionar componentes novos ao Compose quando o Certbot no host resolve o mesmo problema com menor escopo de mudança.

## Consequências

- Nenhum componente novo foi adicionado ao `docker-compose.yml` além do próprio ajuste do Nginx (porta 443, healthcheck). Certbot e Fail2Ban vivem no host, fora do Compose, mantendo a stack do ADR 0001 intacta.
- O certificado (`/etc/letsencrypt`) e os backups (`/opt/backups`) vivem no host da VM, fora do repositório — não há automação de infraestrutura (Terraform/Ansible) para recriar isso em outro host; recriar exige repetir os passos manuais registrados no histórico do projeto.
- A cada vez que o `.env` é alterado, o Docker Compose recria tanto `n8n` quanto `postgres` (por compartilharem o mesmo `env_file`). O `depends_on: condition: service_healthy` entre Nginx e n8n garante que uma subida completa (`docker compose up -d`) sempre inicialize na ordem certa; mas se apenas o `n8n` for recriado isoladamente enquanto o Nginx continuar rodando, o Nginx pode manter em cache o IP interno antigo do container e retornar `502` até um `nginx -s reload` manual — isso não é um bug introduzido por este ADR, é uma limitação do DNS interno do Docker.
- Variáveis `N8N_BASIC_AUTH_*` foram removidas do `.env`/`.env.example` por estarem depreciadas no n8n atual (autenticação passou a ser feita pelo sistema de usuários próprio do n8n).
