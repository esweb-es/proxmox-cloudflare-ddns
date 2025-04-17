#!/bin/bash
set -euo pipefail

# ================================================
# Función: Solicitar entrada con ayuda e info extra
# ================================================
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local help_text="${3:-}"
  local default="${4:-}"
  local input=""

  echo ""
  echo "🔹 $prompt_text"
  [[ -n "$help_text" ]] && echo "   $help_text"
  [[ -n "$default" ]] && echo -n "   (Enter para usar default: $default)"
  echo ""

  while [[ -z "${!var_name:-}" ]]; do
    read -rp "> " input
    input="${input:-$default}"
    if [[ -n "$input" ]]; then
      eval "$var_name=\"\$input\""
    fi
  done
}

# ================================================
# Paso 1: Tokens de Cloudflare
# ================================================
echo "🌐 === CONFIGURACIÓN DE CLOUDFLARE ==="

prompt CF_API_TOKEN \
  "Introduce tu API Token para Cloudflare DDNS (Zone.DNS Edit)" \
  "👉 Genera desde: https://dash.cloudflare.com/profile/api-tokens\n   Usa la plantilla: 'Edit DNS'" 

prompt CF_ZONE_ID \
  "Introduce el Zone ID de tu dominio (Cloudflare DDNS)" \
  "👉 Encuentra el Zone ID en tu dominio desde https://dash.cloudflare.com/" 

prompt CF_RECORD_NAME \
  "Introduce el subdominio a actualizar con DDNS (ej: casa.tudominio.com)" 

echo ""
echo "🔒 Ahora configuraremos el Tunnel Token para Cloudflared."
prompt CF_TUNNEL_TOKEN \
  "Introduce tu Tunnel Token de Cloudflared" \
  "👉 Crea un túnel en https://dash.teams.cloudflare.com → Tunnels → Create Tunnel\n   Copia solo el token del comando: 'cloudflared tunnel --no-autoupdate run --token <ESTE>'" 

# ================================================
# Paso 2: Parámetros del contenedor
# ================================================
echo "🛠️ === CONFIGURACIÓN DEL CONTENEDOR LXC ==="
prompt CT_ID       "ID del contenedor" "" "120"
prompt HOSTNAME    "Nombre del host" "" "cloudflare"
prompt STORAGE     "Almacenamiento (ej: local)" "" "local"
prompt IP_ADDRESS  "IP del contenedor (ej: dhcp o 192.168.1.100/24)" "" "dhcp"
TEMPLATE="debian-12-standard_*.tar.zst"

# ================================================
# Paso 3: Crear y configurar contenedor
# ================================================
echo "📦 Creando contenedor #$CT_ID..."
pct create "$CT_ID" "$(pveam available | grep "$TEMPLATE" | tail -n1 | awk '{print $1}')" \
  -storage "$STORAGE" -hostname "$HOSTNAME" \
  -cores 1 -memory 512 \
  -net0 name=eth0,bridge=vmbr0,ip="$IP_ADDRESS" \
  -features nesting=1 \
  -unprivileged 1

pct start "$CT_ID"
sleep 5

# ================================================
# Paso 4: Instalar Docker en el contenedor
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
# Paso 5: Crear archivo docker-compose.yml
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
echo "🚀 Iniciando servicios Docker..."
pct exec "$CT_ID" -- docker compose -f /opt/cloudflare/docker-compose.yml up -d

echo "✅ Contenedor #$CT_ID listo con Cloudflare DDNS y Cloudflared Tunnel activos."
