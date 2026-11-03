# Uso: source scripts/env.sh
read -s -p "Token da DigitalOcean: " DIGITALOCEAN_TOKEN; echo
export DIGITALOCEAN_TOKEN="$(printf '%s' "$DIGITALOCEAN_TOKEN" | tr -d ' "\r\n')"
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
echo "Token: ${#DIGITALOCEAN_TOKEN} caracteres. Chave SSH carregada."
