#!/bin/bash
set -euo pipefail

# ================================================
# Función: Solicitar entrada con ejemplo
# ================================================
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local example="$3"
  local input=""

  echo ""
  echo "$prompt_text"
  [[ -n "$example" ]] && echo "   Ejemplo: $example"

  while [[ -z "${!var_name:-}" ]]; do
    read -rp "> " input
    if [[ -n "$input" ]]; then
      eval "$var_name=\"\$input\""
    fi
  done
}

# ================================================
# Paso 1: Preguntas clave
# ================================================
echo "🌐 === CONFIGURACIÓN CLOUDFLARE ==="

prompt CF_API_TOKEN "🔑 Token de la API de Cloudflare (para DDNS)" "sUXszATkviRVUpdVfh5QSzCO07PHc47BtPtREz55"
prompt CF_RECORD_NAME "🌍 Dominio o subdominio que deseas actualizar (ej: casa.midominio.com)" "casa.midominio.com"
prompt CF_TUNNEL_TOKEN "🔐 Token del túnel Zero Trust (Cloudflared)" "cloudflared tunnel --no-autoupdate run --token ABC123..."
prompt CT_PASSWORD "🔑 Contraseña del contenedor (root)" ""

# ================================================
# Paso 2: Datos del contenedor
# ================================================
CT_ID=120
HOSTNAME="cloudflare"
STORAGE="local"
IP_ADDRESS="dhcp"
TEMPLATE="debian-12-standard_*.tar.zst"

# ================================================
# Paso 3: Crear contenedor
# ================================================
echo "📦 Creando contenedor #$CT_ID..."
TAR=$(pveam available | grep "$TEMPLATE" | tail -n1 | awk '{print $1}')
pct create "$CT_ID" "$TAR" \
  -storage "$STORAGE" -hostname "$HOSTNAME" \
  -cores 1 -memory 512 \
  -net0 name=eth0,bridge=vmbr0,ip="$IP_ADDRESS" \
  -features nesting=1 \
  -unprivileged 1 \
  -password "$CT_PASSWORD"

pct start "$CT_ID"
sleep 5

# ================================================
# Paso 4: Instalar Docker
# ================================================
echo "🐳 Instalando Docker..."
pct exec "$CT_ID" -- bash -c "
apt update &&
apt install -y curl ca-certificates gnupg lsb-release &&
mkdir -p /etc/apt/keyrings &&
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
apt update &&
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ================================================
# Paso 5: docker-compose.yml
# ================================================
echo "📝 Generando docker-compose.yml..."
pct exec "$CT_ID" -- mkdir -p /opt/cloudflare

pct exec "$CT_ID" -- bash -c "cat > /opt/cloudflare/docker-compose.yml" <<EOF
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
# Paso 6: Iniciar servicios
# ================================================
echo "🚀 Iniciando servicios Docker..."
pct exec "$CT_ID" -- docker compose -f /opt/cloudflare/docker-compose.yml up -d

echo "✅ Contenedor #$CT_ID listo con Docker, DDNS y Tunnel de Cloudflare."
