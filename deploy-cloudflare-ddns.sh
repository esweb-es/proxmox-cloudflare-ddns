#!/bin/bash
set -euo pipefail

# ================================================
# Función: Solicitar entrada con validación
# ================================================
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local input=""

  while [[ -z "${!var_name:-}" ]]; do
    read -rp "$prompt_text ${default:+[$default]}: " input
    input="${input:-$default}"
    if [[ -n "$input" ]]; then
      eval "$var_name=\"\$input\""
    fi
  done
}

# ================================================
# Paso 1: Solicitar datos necesarios
# ================================================
echo "=== CONFIGURACIÓN CLOUDFLARE ==="
prompt CF_API_TOKEN      "🔑 Introduce tu API Token de Cloudflare (permiso: Zone.DNS + Account)" 
prompt CF_ZONE_ID        "🌐 Introduce tu Zone ID de Cloudflare"
prompt CF_RECORD_NAME    "📝 Introduce el subdominio a actualizar con DDNS (ej: casa.midominio.com)"
prompt CF_TUNNEL_TOKEN   "🔒 Introduce el Tunnel Token de Cloudflared (https://dash.cloudflare.com/ -> Zero Trust -> Tunnels)"

# ================================================
# Paso 2: Parámetros del contenedor
# ================================================
echo "=== CONFIGURACIÓN DEL CONTENEDOR LXC ==="
prompt CT_ID          "🆔 ID del contenedor (ej: 120)"
prompt HOSTNAME       "📛 Nombre del host"          "cloudflare"
prompt STORAGE        "💾 Almacenamiento (ej: local)" "local"
prompt IP_ADDRESS     "🌐 IP del contenedor (ej: dhcp o 192.168.1.100/24)" "dhcp"
TEMPLATE="debian-12-standard_*.tar.zst"

# ================================================
# Paso 3: Crear contenedor
# ================================================
echo "✅ Creando contenedor LXC #$CT_ID..."

pct create "$CT_ID" "$(pveam available | grep "$TEMPLATE" | tail -n1 | awk '{print $1}')" \
  -storage "$STORAGE" \
  -hostname "$HOSTNAME" \
  -cores 1 -memory 512 -net0 name=eth0,bridge=vmbr0,ip="$IP_ADDRESS" \
  -features nesting=1 \
  -unprivileged 1

pct start "$CT_ID"
sleep 5

# ================================================
# Paso 4: Instalar Docker en el contenedor
# ================================================
echo "🐳 Instalando Docker dentro del contenedor..."
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
# Paso 5: Crear docker-compose.yml
# ================================================
echo "📦 Configurando servicios Docker..."

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
      - ZONE=$CF_ZONE_ID
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
echo "🚀 Iniciando servicios..."
pct exec "$CT_ID" -- docker compose -f /opt/cloudflare/docker-compose.yml up -d

echo "✅ Contenedor #$CT_ID con Cloudflare DDNS y Cloudflared configurado."
