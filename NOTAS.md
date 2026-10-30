## Dia 1 — Postgres e Redis locais

### O que fiz
- Subi Postgres 16 e Redis 7 com Docker Compose.
- `init.sql` montado em `/docker-entrypoint-initdb.d/` cria um database por app
  (n8n, keycloak, evolution).

### O que aprendi
- O `init.sql` só roda quando o volume está vazio (primeira subida).
- Container é descartável; volume é persistente:
  - `docker compose down` + `up` → dados continuam (testei com uma tabela `teste`).
  - `docker compose down -v` → volume apagado, banco nasce do zero.
- Healthcheck (`pg_isready`) + `depends_on: condition: service_healthy`
  fazem os apps esperarem o banco estar pronto.

### Erros e como resolvi
- **Postgres e Redis reiniciando em loop:** o `.env` não existia na pasta `stack`.
  Sem `POSTGRES_PASSWORD`, o Postgres se recusa a iniciar.
  Pista: avisos `variable is not set` no `docker compose`.
  Ferramenta útil: `docker compose config` mostra o arquivo com as variáveis já substituídas.
- **`no configuration file provided`:** estava na pasta errada; o compose.yaml fica em `stack/`.

## Dia 3 — Traefik e os apps open source

### O que fiz
- Traefik como proxy reverso: único serviço com porta publicada (80).
- n8n (`n8n.localhost`), Keycloak (`auth.localhost`) e Evolution API (`wpp.localhost`)
  roteados por labels.
- Fluxo no n8n chamando a Evolution API pela rede interna.

### O que aprendi
- O Traefik decide o destino pelo cabeçalho `Host` da requisição.
- Peças do Traefik: entrypoint (porta de entrada) → router (regra) →
  middleware (filtros) → service (destino).
- Cada app se apresenta ao Traefik pelas próprias labels; o Traefik lê o
  Docker pelo `docker.sock`.
- Dois "mundos" de endereço:
  - De fora: domínios (`wpp.localhost`), resolvidos pelo navegador e roteados pelo Traefik.
  - De dentro: nomes de serviço (`evolution-api`, `postgres`), resolvidos pelo DNS interno do Docker.
  - Dentro de um container, `localhost` é o próprio container.
- Credenciais no n8n ficam criptografadas com o `N8N_ENCRYPTION_KEY`;
  melhor que colar a chave direto no nó.

### Erros e como resolvi
- **404 em tudo, mesmo com a rota certa:** o Traefik v3.1 não conseguia falar com o
  Docker Engine atual (log: `Failed to retrieve information of the docker client`).
  Atualizei para `traefik:v3.6`.
  Lição: fixar versão garante repetibilidade, mas a versão precisa ser atualizada de
  propósito quando o ambiente muda.
- **Imagem da Evolution API mudou de nome:** de `atendai/evolution-api` para
  `evoapicloud/evolution-api` (a partir da v2.3.0). Sempre conferir a documentação atual.
- **`source .env` dava `command not found`:** valor com espaço sem aspas.
  Regra: no `.env`, usar aspas em valores com espaço.
- **`400 Bad Request` no curl:** o `.env` estava com quebra de linha do Windows (CRLF),
  e o `\r` invisível ia parar no cabeçalho HTTP.
  Diagnóstico: `file .env`. Correção: `sed -i 's/\r$//' .env` e VS Code em LF.
- **Senhas dentro de URIs** (`postgresql://user:senha@host`): evitar `@ : / ? #`.
  Uso `openssl rand -hex 24` para gerar senhas só com letras e números.