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

## Dia 4 — Load balancer, API gateway e redes separadas

### O que fiz
- API própria publicada em `gw.localhost/api`, com 3 réplicas atrás do Traefik
  (`docker compose up -d --scale api=3`).
- Middlewares no Traefik: remoção de prefixo (`stripprefix`), limite de taxa
  (`ratelimit`) e autenticação (`basicauth`).
- Painel do Traefik em `traefik.localhost`, protegido por usuário e senha.
- Redes separadas: `proxy` (Traefik + apps) e `backend` (apps + Postgres + Redis).

### O que aprendi
- **Proxy reverso** fica do lado do servidor: recebe tudo e repassa ao container certo.
- **Load balancer** é um proxy reverso que distribui requisições entre cópias do
  mesmo serviço (round robin) e tira da roda as que caem.
- **API gateway** decide quem passa e com quais regras, usando middlewares.
  Aqui o Traefik faz os três papéis.
- **Labels** são etiquetas chave=valor; o Docker só guarda, o Traefik lê e monta
  as rotas. A configuração de cada rota mora junto do próprio app.
- **Tolerância a falha:** derrubei uma réplica no meio de um laço de requisições
  e nenhuma falhou; o Traefik tirou ela da roda na hora.
  - `docker stop` respeita o `restart: unless-stopped` (não volta sozinho).
  - `docker kill` simula uma queda (volta sozinho).
- **Rate limit:** numa rajada de 60 requisições, parte voltou `429 Too Many Requests`.
- **Redes separadas = menor privilégio.** O Traefik, única peça exposta, não
  alcança o banco (`ping postgres` de dentro dele dá `bad address`).
  Reduz o "raio de explosão" se ele for comprometido.
- **Ler códigos HTTP:**
  - `404` → nenhuma rota combinou.
  - `401` → a rota existe, mas pediu autenticação.
  - `502 Bad Gateway` → o Traefik alcançou o container, mas ninguém respondeu
    (app subindo ou caído).
  - `504 Gateway Timeout` → o Traefik não alcançou o container (rede errada).
- **Senhas do painel:** o Traefik guarda só o hash (gerado com `htpasswd`), nunca a
  senha. `htpasswd -n admin` pede a senha sem deixá-la no histórico do terminal.

### Erros e como resolvi
- **`services.include must be a mapping`:** colei o `include:` dentro de `services:`.
  Validar sempre com `docker compose config -q` depois de editar o YAML.
- **`504` no n8n e no Keycloak depois de separar as redes:** com duas redes, o
  Traefik às vezes usava o IP da `backend`, que ele não alcança.
  Correção: `--providers.docker.network=pdi_proxy` no Traefik.
- **`502` no Keycloak:** ele ainda estava subindo (recompila a configuração ao ser
  recriado). Esperar a linha `Listening on` nos logs.
- **Laço de `curl` com linhas vazias:** digitei `http//` sem os dois-pontos, e o
  `-s` escondeu o erro. Quando um comando silencioso não mostra nada, rodar sem `-s`.
- **`upp` em vez de `up`:** o Compose só mostrou a ajuda.
- **Hash da senha no repositório público:** coloquei no `.env` (fora do Git), entre
  aspas simples, para o Compose não interpretar os `$`. O ponto final faz parte do hash.
- **`docker compose restart` não aplica labels novas:** é preciso `up -d` para
  recriar o container com a configuração atual.

  ## Dia 5 — Terraform cria o Droplet na DigitalOcean

### O que fiz
- Escrevi `versions.tf`, `variables.tf`, `main.tf` e `outputs.tf` para a DigitalOcean:
  chave SSH, Droplet (`s-2vcpu-4gb`, Ubuntu 24.04, `nyc1`) e firewall.
- Rodei o ciclo completo: `init` → `plan` → `apply` → `ssh` → `destroy`.
- Criei `scripts/env.sh` para preparar o terminal (token + chave SSH) com
  `source scripts/env.sh`.

### O que vi acontecer
- `plan`: `3 to add` (chave SSH, Droplet e firewall). Campos como `id` e
  `ipv4_address` aparecem como `(known after apply)`: só existem depois de criados.
- `apply`: o Terraform criou na ordem certa sozinho, sem eu dizer:
  chave SSH (2s) → Droplet (23s) → firewall (1s).
  O firewall depende do ID do Droplet, e o Droplet depende da chave.
  Ele monta esse grafo de dependências lendo as referências no código.
- Output: `server_ip` com o IP público, usado direto no
  `ssh root@$(terraform output -raw server_ip)`.
- Dentro do servidor: 2 vCPUs, ~3.8 GB de RAM, disco de 80 GB.
- `destroy`: ordem inversa (firewall → Droplet → chave), `3 destroyed`.
  O plano de destruição mostrou o que o state guardava: IDs, IPs (público e
  privado), preço por hora (US$ 0,03571) e mensal (US$ 24).
- Na primeira conexão SSH, o `ssh` pediu para confirmar a impressão digital do
  servidor e a guardou em `~/.ssh/known_hosts`. Num servidor recriado, o IP pode
  repetir com outra impressão digital, e o SSH vai reclamar.

### O que aprendi
- **IaC na prática:** o servidor existe porque o código diz que existe.
  Apagar e recriar é um comando.
- **`plan` antes de `apply`, sempre.** O `plan` não testa o token para
  recursos novos (só compara o código com o state vazio); o erro de
  autenticação só apareceu no `apply`.
- **State (`terraform.tfstate`)** é o caderno do Terraform: guarda o que ele
  criou, inclusive dados sensíveis. Fica fora do Git.
- **`.terraform.lock.hcl`** fixa a versão exata dos providers e vai para o Git.
- **Segredos x não segredos:** token só em variável de ambiente;
  domínio, e-mail e URL do repo no `terraform.tfvars` (fora do Git).
- **Firewall da DigitalOcean bloqueia nos dois sentidos:** sem `outbound_rule`,
  o Droplet não acessa a internet.
- `TF_VAR_nome` passa valores para a variável `nome` do Terraform.
- Variáveis de ambiente valem só no terminal onde foram criadas.

### Erros e como resolvi
- **`Invalid multi-line string` no `terraform.tfvars`:** faltou fechar aspas.
  `terraform fmt` acha esse tipo de erro rápido.
- **`401 Unable to authenticate you`:** o token tinha 74 caracteres em vez de 71.
  Causa: `Ctrl + V` não cola no terminal do Linux, ele insere caracteres de
  controle invisíveis. No terminal: `Ctrl + Shift + V` ou botão direito.
  Diagnóstico sem expor o token: `echo ${#DIGITALOCEAN_TOKEN}` (só o tamanho)
e `curl` em `/v2/account` (200 = token válido).
- **Terraform perguntando `var.ssh_public_key`:** abri um terminal novo e as
  variáveis não estavam lá. Solução: `source scripts/env.sh` em todo terminal novo.
- **`No configuration files`:** rodei o `terraform` fora da pasta `terraform/`.
- **Terminal abrindo no PowerShell:** entrei no Ubuntu digitando `wsl`.  

## Dia 6 — cloud-init: o servidor nasce pronto

### O que fiz
- Template `terraform/cloud-init.yaml.tftpl`: usuário `deploy`, hardening do SSH,
  UFW, fail2ban, Docker, clone do repositório, `.env` e `docker compose up`.
- Senhas geradas pelo Terraform (`random_password`), passadas ao template via
  `templatefile` e gravadas no `/opt/pdi/.env` do Droplet.
- Saídas `sensitive` para consultar senhas: `terraform output -raw keycloak_admin_password`.
- Resultado: `terraform apply` → em poucos minutos, 7 serviços `Up` no Droplet,
  sem eu digitar nenhum comando de instalação dentro dele. Só o Traefik com porta publicada.

### O que aprendi
- **Dois YAML, dois papéis:** o cloud-init prepara a máquina no primeiro boot;
  o Compose sobe os containers. O cloud-init chama o Compose no fim.
- **`${nome}` só no template (`.tftpl`):** o Terraform preenche.
  No `.env` local vão os valores de verdade.
- **Heredoc:** `<< EOF` (sem aspas) executa `$(...)` e expande variáveis antes
  de gravar; `<< 'EOF'` (com aspas) grava o texto literal.
- **O Droplet só conhece o que está no GitHub:** commit e push antes do `apply`.
- **Mudar o `user_data` recria o Droplet:** o cloud-init só roda no primeiro boot.
- **Corrigir na origem e recriar** é melhor que remendar o servidor à mão.
- **Grupos do Linux são lidos no login:** depois do `usermod`, é preciso sair e
  entrar de novo (ou `newgrp docker`).
- **O cloud-init roda tudo como root:** arquivos criados por ele pertencem ao root.
- `sudo cloud-init status --wait` espera o primeiro boot terminar.

### Erros e como resolvi
- **`422 Size is not available in this region`:** sem capacidade do plano em `nyc1`
  e `nyc3`. Consultei a API (`/v2/sizes`) e troquei para `tor1` no `terraform.tfvars`.
  A região como variável permitiu contornar com uma linha.
- **`no file exists at cloud-init.yaml.tftpl`:** o arquivo estava como `yamal`.
- **Template colado no `stack/.env` local:** quebrou o ambiente local e deixou o
  hash do Traefik vazio. Recriei o `.env` com senhas novas (`openssl rand -hex 24`).
- **Painel do Traefik com `no users found`:** o `TF_VAR_traefik_dashboard_auth`
  estava vazio no `apply`. Acrescentei `validation` na variável: agora o `plan`
  para com mensagem clara.
- **`open /opt/pdi/.env: permission denied`:** o `.env` pertencia ao root.
  Acrescentei `chown deploy:deploy /opt/pdi/.env` ao `runcmd`.
- **`503` na API:** ela estava na rede `backend`, e a correção não tinha ido
  para o GitHub. Rodei comandos de Git dentro do Droplet por engano (prompt
  `deploy@pdi-app`). Agora uso dois terminais: um para o PC, outro para o servidor.
  