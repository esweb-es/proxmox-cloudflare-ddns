#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
APP="Cloudflare-DDNS"
var_tags="docker ddns cloudflare"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

# ========================
# Preguntas al usuario
# ========================
read -rp "🔐 Ingresa tu API Key de Cloudflare: " CF_API_KEY
read -rp "🌐 Ingresa tu dominio (ZONE) en Cloudflare (ej: midominio.com): " CF_ZONE
read -rp "🧩 Ingresa el subdominio (SUBDOMAIN) que quieres usar (ej: casa): " CF_SUBDOMAIN

# ========================
# Fijar storage directamente
# ========================
DETECTED_STORAGE="local-lvm"

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  pveam update
  pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)
pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname cloudflare-ddns \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# ========================
# Instalar Docker dentro del contenedor
# ========================
lxc-attach -n $CTID -- bash -c "
  apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Docker Compose: Cloudflare DDNS
# ========================
lxc-attach -n $CTID -- bash -c "
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

msg_ok "✅ Cloudflare DDNS desplegado correctamente en el contenedor LXC #$CTID"
echo -e "${INFO}${YW} Está sincronizando en el dominio: ${CF_SUBDOMAIN}.${CF_ZONE}${CL}"
