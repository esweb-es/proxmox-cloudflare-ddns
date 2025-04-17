#!/bin/bash
set -euo pipefail

# ================================================
# Pide datos
# ================================================
read -rp "🔐 API Token de Cloudflare (Zone.DNS Edit): " CF_API_TOKEN
read -rp "🌍 Subdominio a actualizar (ej: casa.tudominio.com): " CF_RECORD_NAME
read -rp "🛡️ Token del túnel (Cloudflared Tunnel Token): " CF_TUNNEL_TOKEN
read -rp "🔑 Contraseña root del contenedor: " CT_PASSWORD

# ================================================
# Parámetros del contenedor
# ================================================
CT_ID=120
HOSTNAME="cloudflare"
STORAGE="local"
IP_CONFIG="dhcp"
TEMPLATE=$(pveam available | grep debian-12 | grep standard | tail -n1 | awk '{print $1}')

# ================================================
# Crear contenedor
# ================================================
echo "📦 Creando contenedor #$CT_ID..."
pveam download local $TEMPLATE
pct create $CT_ID local:vztmpl/$TEMPLATE \
  -hostname $HOSTNAME \
  -net0 name=eth0,bridge=vmbr0,ip=$IP_CONFIG \
  -cores 1 -memory 512 \
  -features nesting=1 \
  -unprivileged 1 \
  -password "$CT_PASSWORD" \
  -storage $STORAGE

pct start $CT_ID
sleep 5

# ================================================
# Instalar Docker
# ================================================
echo "🐳 Instalando Docker..."
pct exec $CT_ID -- bash -c "
apt update &&
apt install -y ca-certificates curl gnupg lsb-release &&
install -m 0755 -d /etc/apt/keyrings &&
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
chmod a+r /etc/apt/keyrings/docker.gpg &&
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
apt update &&
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

# ================================================
# Crear docker-compose.yml
# ================================================
echo "📝 Generando docker-compose.yml..."
pct exec $CT_ID -- mkdir -p /opt/cloudflare

pct exec $CT_ID -- bash -c "cat > /opt/cloudflare/docker-compose.yml" <<EOF
version: '3'
services:
  cloudflare-ddns:
    image: oznu/cloudflare-ddns
    container_name: cloudflare-ddns
    restart: always
    environment:
      - API_KEY=$CF_API_TOKEN
      - SUBDOMAIN=$CF_RECORD_NAME

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: always
    command: tunnel --no-autoupdate run --token $CF_TUNNEL_TOKEN
EOF

# ================================================
# Iniciar los servicios
# ================================================
echo "🚀 Iniciando servicios Docker..."
pct exec $CT_ID -- docker compose -f /opt/cloudflare/docker-compose.yml up -d

echo -e "\n✅ Contenedor #$CT_ID desplegado con Cloudflare DDNS y Tunnel funcionando."
