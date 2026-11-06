#!/usr/bin/env bash
# Uso: ./scripts/wait-ready.sh https://n8n.SEU-DOMINIO
# Espera a URL responder com sucesso e mostra quanto tempo levou.
URL="$1"
LIMITE=900   # desiste depois de 15 minutos
INICIO=$(date +%s)

if [ -z "$URL" ]; then
  echo "Uso: $0 URL"
  exit 1
fi

echo "Aguardando $URL ..."
until curl -sfk -o /dev/null "$URL"; do
  AGORA=$(date +%s)
  if [ $((AGORA - INICIO)) -ge $LIMITE ]; then
    echo "Desisti depois de $LIMITE segundos. Veja os logs do cloud-init no servidor."
    exit 1
  fi
  echo "  ainda não respondeu ($((AGORA - INICIO))s)..."
  sleep 10
done

FIM=$(date +%s)
echo "Pronto! $URL respondeu em $((FIM - INICIO)) segundos."
