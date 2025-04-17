#!/bin/bash
set -euo pipefail

# ================================================
# CONFIGURACIÓN INICIAL
# ================================================
echo "=== Cloudflare DDNS + Tunnel en LXC (Docker) ==="

read -rp "🔐 API Token de Cloudflare (DDNS, Zone.DNS Edit): " CF_API_TOKEN
read -rp "🌐 Dominio o subdominio a actualizar (ej: casa.midominio.com): " CF_RECORD_NAME
read -rp "🔒 Tunnel Token de Cloudflare Zero Trust: " CF_TUNNEL_TOKEN
read -rp "🔑 Contraseña del contenedor: " CT_PASSWORD

# ================================================
# PARÁMETROS DEL CONTENEDOR
# ================================================
CT_ID=120
CT_NAME=cloudflare
STORAGE=local
TEMPLATE="debian-12-standard_12.0-1_amd64.tar.zst"
IP_TYPE="dhcp"

# ================================================
# CREAR CONTENEDOR
# ================================================
echo "🛠️ Creando contenedor LXC..."
pveam update
TAR=$(pveam available | grep "$TEMPLATE" | tail -n1 | awk '{print $1}')
pct create $CT_ID $TAR \
  -storage $STORAGE \
  -hostname $CT_NAME \
  -net0 name=eth0,bridge=vmbr0,ip=$IP_TYPE \
  -cores 1 -memory 512 \
  -features nesting=1 \
  -unprivileged 1 \
  -password "$CT_PASSWORD"

pct start $CT_ID
sleep 5

# ================================================
# INSTALAR DOCKER
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
# CREAR docker-compose.yml
# ================================================
echo "📦 Generando docker-compose.yml..."
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
# INICIAR SERVICIOS
# ================================================
echo "🚀 Iniciando servicios..."
pct exec $CT_ID -- docker compose -f /opt/cloudflare/docker-compose.yml up -d

echo "✅ ¡Contenedor $CT_ID con DDNS y Tunnel funcionando!"
