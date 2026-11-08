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

## Dia 7 — DNS e HTTPS

### O que fiz
- DNS com DuckDNS: `curl` na API do DuckDNS depois do `apply` aponta
  `pdi-dogabriel.duckdns.org` (e qualquer subdomínio) para o IP do Droplet.
- HTTPS com Let's Encrypt (staging) pelo Traefik: entrypoint `websecure` (443),
  redirecionamento HTTP → HTTPS (308) e resolver `le` com desafio HTTP.
- Labels `entrypoints=websecure` e `tls.certresolver=le` em cada router.
- `PROTOCOL=https` no template do cloud-init.

### O que aprendi
- **Registro curinga:** um único `*` aponta todos os subdomínios para o mesmo IP;
  quem separa os apps é o Traefik, pelo `Host`.
- **TTL curto (60s):** quando o IP muda numa recriação, o mundo descobre rápido.
- **Desafio HTTP do ACME:** o Let's Encrypt chama `http://dominio/.well-known/...`
  na porta 80 para provar que eu controlo o domínio. Por isso a porta 80 continua aberta.
- **Staging x produção:** staging não tem limite de emissões, mas o certificado não é
  confiável (aviso no navegador). Produção só na subida final, porque há limite de
  certificados repetidos por semana.
- `openssl s_client ... | grep issuer` mostra quem emitiu o certificado.
- `curl -k` aceita qualquer certificado: um `200` com `-k` não prova que o certificado
  é o certo.
- Aba anônima evita o cache de DNS e de HTTPS do navegador.

### Erros e como resolvi
- **`404 domain not found` no `digitalocean_record`:** o `terraform.tfvars` estava com
  o domínio de exemplo, e esse recurso só serve para domínio com DNS na DigitalOcean.
  Com DuckDNS, removi o bloco.
- **`KO` no DuckDNS:** o token não estava carregado. Acrescentei o pedido do token ao
  `env.sh`, que agora mostra o tamanho dos três segredos no fim.
- **`404` no HTTPS:** linhas da lista de labels com recuo maior grudaram na linha de cima
  (`Host(...) - traefik.http.routers...`). O YAML continua válido, então o
  `docker compose config -q` não acusa; só o Traefik percebe. Diagnóstico: logs do
  Traefik e `docker compose config` completo.
- **`acme.json: no such file or directory`:** o volume `letsencrypt` não estava montado,
  e o resolver foi desligado. Corrigi o bloco `volumes:` do Traefik.
- **Corrigi o Droplet sem recriá-lo:** como só o `compose.yaml` mudou, bastou
  `git pull` + `docker compose up -d` no servidor.  

## Dia 8 — O "um clique"

### O que fiz
- **Makefile** com `make up`, `make down`, `make recreate` e `make ssh`.
  O `up` faz `init` → `apply` → atualiza o DuckDNS → espera o n8n responder.
- **`scripts/wait-ready.sh`:** tenta a URL a cada 10 segundos (com limite de
  15 minutos) e mostra quanto tempo a stack levou para responder.
- **State remoto no HCP Terraform:** workspace `infra-pdi`, com Execution Mode
  **Local** (o Terraform roda na minha máquina ou no GitHub e só guarda o state lá).
- **Botão no GitHub Actions** (`.github/workflows/infra.yml`), com
  `workflow_dispatch` e escolha entre `up`, `down` e `recreate`.

### Resultado
- **Do zero ao ar em 7 minutos** (`time make up`: `real 7m0s`).
  - Terraform: ~37 segundos.
  - cloud-init (pacotes, Docker, clone, imagens, stack): 383 segundos.
  - O gargalo é o primeiro boot, não o Terraform. Ideias para encurtar: tirar o
    `package_upgrade`, usar imagem com Docker pronto, publicar as imagens num
    registry em vez de fazer build no servidor.
- `up` e `down` funcionando pelo botão, sem nenhum comando no terminal.

### O que aprendi
- **Makefile:** as linhas de comando começam com TAB (com espaços dá
  `missing separator`). `$` precisa ser dobrado (`$$`) quando é para o bash, não
  para o Make. `DOMAIN ?=` usa o valor do ambiente se existir; senão, lê o `tfvars`.
  `up: init` faz o `init` rodar antes do `up`.
- **Por que state remoto:** cada execução do GitHub Actions roda numa máquina nova,
  apagada no fim. Com state local, o `down` pelo botão não saberia o que destruir.
- **Execution Mode Local x Remote:** no modo Remote, o Terraform rodaria nos
  servidores da HashiCorp, sem acesso aos meus tokens e variáveis.
- **Histórico de states:** cada `apply` e `destroy` gera uma versão nova no
  HCP Terraform. Dá para ver o ambiente ao longo do tempo.
- **O state é compartilhado:** depois do `up` pelo GitHub, o
  `terraform output -raw server_ip` no meu computador mostrou o IP do Droplet
  que o GitHub criou.
- **Secrets x Variables no GitHub:** secrets ficam escondidos (`***` nos logs) e
  nunca mais são exibidos; variables são visíveis e servem para o que não é segredo.
- **Um token por lugar:** `wsl-gabriel` (meu computador) e
  `github-actions-infra-pdi` (GitHub). Se um vazar, revogo só ele.
  Tokens do HCP Terraform só aparecem uma vez: se esquecer, gera outro.
- **`concurrency` no workflow:** impede duas execuções ao mesmo tempo mexendo
  no mesmo state. **`timeout-minutes`:** para a execução se algo travar.

### Erros e como resolvi
- **`422 Size is not available in this region` (agora em `tor1`):** a capacidade
  muda ao longo do dia. A lista da API mostra onde o plano é oferecido, não onde
  há máquina livre naquele minuto. Troquei a região de novo.
- **State "vazio" no HCP Terraform depois do `init`:** normal. O state local não
  tinha recursos (eu tinha feito `make down`), e o Terraform não envia state vazio.
  O primeiro state apareceu no primeiro `apply`.
- **`down` pelo botão falhou com `initialization required`:** o alvo `down` não
  rodava `init`. No meu computador funcionava porque a pasta `.terraform/` já
  existia; no GitHub, a máquina começa vazia. Correção: alvo `init` e todos os
  outros dependendo dele.
  Lição: funcionar na minha máquina não garante funcionar no CI.
- **Esse erro deixou o Droplet ligado (e cobrando):** depois de qualquer falha no
  `down`, conferir o painel da DigitalOcean.

## Dia 9 — Escalonamento vertical e horizontal

### Parte A — Vertical (máquina maior)

**O que fiz:** com a stack no ar, rodei
`terraform apply -var size=s-4vcpu-8gb`, com `resize_disk = false` no Droplet.

**O que vi:**
- O `plan` mostrou `~ update in-place`: o mesmo servidor, mesmo IP, mesmos dados.
  Só o `size` mudou (`s-2vcpu-4gb` → `s-4vcpu-8gb`).
- A operação levou **1 minuto e 35 segundos**. Nesse tempo, o Droplet ficou
  desligado: a stack ficou **fora do ar**.
- Depois: 4 vCPUs e 8 GB de RAM. Os containers voltaram sozinhos
  (`restart: unless-stopped`).
- Preço: de **US$ 0,03571/h** para **US$ 0,07143/h** (US$ 24 → US$ 48 por mês).
  O dobro.
- Antes, consultei a API para confirmar que o plano maior existia na região.

**O que aprendi:**
- `resize_disk = false` aumenta só CPU e RAM. Sem ele, o disco cresce junto e
  nunca mais pode diminuir, e não dá para voltar ao plano menor.
- **`-var` vale só para aquele comando.** No `make up` seguinte, o Terraform voltou
  ao tamanho do `tfvars`. Para uma mudança permanente, o valor vai no `tfvars`
  (ou numa variável do GitHub), não no `-var`.

### Parte B — Horizontal (mais máquinas, Docker Swarm)

**O que fiz:**
- Terraform: VPC (`10.10.10.0/24`), workers com `count = var.worker_count`,
  firewall cobrindo todos os Droplets e liberando a rede privada entre eles,
  saídas `app_private_ip` e `worker_ips`.
- cloud-init: `ufw allow from` a VPC no app e nos workers; template próprio e
  mais enxuto para os workers (sem stack, sem `.env`, sem `package_upgrade`).
- Imagem da API publicada no GitHub Container Registry
  (`ghcr.io/machadox18/pdi-api:1.0`), pública.
- `stack/stack.yaml`: versão da stack para o Swarm.
- `make swarm`: `docker swarm init` no manager (pelo IP privado) e
  `docker swarm join` em cada worker.

**O que vi:**
- `make up`: o Droplet foi **recriado** (`must be replaced`), porque entrar na VPC
  (`vpc_uuid`) e mudar o cloud-init (`user_data`) forçam a recriação.
  Stack no ar em **340 segundos**.
- Worker criado em 23 segundos com `apply -var worker_count=1`, sem tocar no manager.
- `make swarm`: `Swarm initialized` no manager e `joined a swarm as a worker` no worker.
- `docker node ls`: 2 nós `Ready`, o `pdi-app` como `Leader`.
- `docker stack deploy`: 7 serviços criados; a API com **4 réplicas divididas**
  entre `pdi-app` e `pdi-worker-1`.
- `docker service scale pdi_api=8`: 8 réplicas, 4 em cada servidor,
  convergido em segundos.
- `docker node update --availability drain pdi-worker-1`: as 4 réplicas do worker
  foram para `Shutdown`, e o Swarm criou 4 novas no manager na mesma hora.

**O que aprendi:**
- **Swarm = cluster de servidores Docker.** O manager decide onde cada container
  roda; o worker só executa. O cluster se comunica pela rede privada.
- **Rede overlay:** liga containers de servidores diferentes como se estivessem
  lado a lado.
- **No Swarm não existe `build`:** cada servidor baixa a imagem pronta de um registry.
- **Volumes são locais:** Postgres, Traefik e Evolution ficam presos ao manager
  (`placement.constraints: [node.role == manager]`), senão perderiam os dados ao
  mudar de servidor.
- **No Swarm, as labels ficam dentro de `deploy:`**, o Traefik usa
  `--providers.swarm` e exige a label de porta mesmo no painel.
- `docker stack deploy` não lê o `.env`: é preciso carregar antes
  (`set -a; . /opt/pdi/.env; set +a`).
- Mesmo nome de stack (`pdi`) = mesmos nomes de volume do Compose: os dados e o
  certificado do manager foram reaproveitados.
- **`drain`** tira um servidor da roda para manutenção, e o cluster redistribui
  as réplicas sozinho.

### Comparação

| | Vertical | Horizontal |
| --- | --- | --- |
| Tempo fora do ar | ~1min35s (Droplet desligado no resize) | Nenhum: no `drain`, réplicas recriadas no outro servidor na hora |
| Custo por hora | Dobrou (US$ 0,036 → 0,071) | Soma o preço de um worker menor |
| Limite | O maior Droplet disponível | Praticamente sem limite (mais workers) |
| O que precisou mudar | Uma variável | VPC, firewall, cloud-init, registry, Swarm e arquivo de stack |

**Conclusão:** o vertical é simples, mas para o serviço e tem teto. O horizontal
escala sem parar e quase sem limite, mas exige muito mais preparo. É por isso que
existem orquestradores como Swarm e Kubernetes.

### Erros e como resolvi
- **`Blocks of type "variable" are not expected here`:** colei o `worker_count`
  dentro do bloco de outra variável. Reescrevi o `variables.tf` com cada bloco
  fechado antes do próximo. `terraform fmt` ajuda a ver a indentação torta.
- **`docker: command not found` no Ubuntu:** o Docker Desktop estava fechado.
- **`read -s` com várias linhas coladas de uma vez:** ele pode "comer" a linha
  seguinte como se fosse o valor. Rodar o `read` sozinho e conferir o tamanho.
- **`invalid reference format`:** um `~` no fim do nome da imagem.
- **`denied` no push para o GHCR (as camadas subiam, o manifesto não):** o token
  estava certo (`write:packages`). A causa era o manifesto de atestado que o Docker
  Desktop envia. Resolvido com `docker build --provenance=false`.
- **`This node is not a swarm manager`:** rodei `docker node ls` no meu computador.
  Comandos de cluster vão no manager (`make ssh`).
- **`exit` + `make down` colados juntos:** o `make down` não rodou e os servidores
  ficaram ligados. Sempre confirmar no painel depois de destruir.

### Para a apresentação
- Repetir o `drain` com um laço de `curl` rodando ao lado, para mostrar que
  nenhuma requisição falha.
- Medir o tempo fora do ar do vertical com o laço de `curl` (`grep -c " 000"`).    
  