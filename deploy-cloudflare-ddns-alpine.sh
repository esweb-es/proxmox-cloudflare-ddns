#!/usr/bin/env bash

# Ejecuta el script oficial para crear el contenedor LXC con Alpine y Docker
bash -c "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/alpine-docker.sh)"

# Preguntas al usuario (como en tu script original)
read -rp "🔐 Ingresa tu API Key de Cloudflare: " CF_API_KEY
read -rp "🌐 Ingresa tu dominio (ZONE) en Cloudflare (ej: midominio.com): " CF_ZONE
read -rp "🧩 Ingresa el subdominio (SUBDOMAIN) que quieres usar (ej: casa): " CF_SUBDOMAIN

# Detectar el último CTID creado (puedes hacerlo de muchas formas, aquí simple):
CTID=$(pvesh get /cluster/resources --type vm | grep alpine | awk '{print $1}' | sed 's/.*-//')

# Espera que el contenedor arranque
sleep 5

# Instalar docker-compose y crear el contenedor de Cloudflare-DDNS dentro del LXC
lxc-attach -n $CTID -- sh -c "
  apk add --no-cache docker-cli-compose
  mkdir -p /opt/ddns && cd /opt/ddns
  cat <<EOF > docker-compose.yml
version: '3'
services:
  cloudflare-ddns:
    image: oznu/cloudflare-ddns:latest
    restart: always
    environment:
      - API_KEY=${CF_API_KEY}
      - ZONE=${CF_ZONE}
      - SUBDOMAIN=${CF_SUBDOMAIN}
      - PROXIED=false
EOF

  docker compose up -d
"

echo "✅ Cloudflare DDNS desplegado correctamente en el contenedor Alpine LXC #$CTID"
