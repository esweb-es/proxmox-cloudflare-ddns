#!/usr/bin/env bash

# ========================
# Funciones básicas sin dependencias externas
# ========================
function msg_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

function msg_ok() {
  echo -e "\033[1;32m[OK]\033[0m $1"
}

function msg_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# ========================
# Variables básicas
# ========================
APP="Cloudflare-DDNS / Cloudflared Tunnel"
CT_HOSTNAME="cloudflare-stack"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
DETECTED_STORAGE="local-lvm"
var_cpu="1"
var_ram="512"
var_disk="2"
var_unprivileged="1"

msg_info "Desplegando: $APP"

# ========================
# Preguntas al usuario
# ========================
read -rp "❓ ¿Quieres instalar Cloudflare DDNS? [s/n]: " INSTALL_DDNS
INSTALL_DDNS=${INSTALL_DDNS,,}

if [[ "$INSTALL_DDNS" == "s" ]]; then
  read -rp "🔐 Ingresa tu API Key de Cloudflare: " CF_API_KEY
  read -rp "🌐 Ingresa tu dominio (ZONE) en Cloudflare (ej: midominio.com): " CF_ZONE
  read -rp "🧩 Ingresa el subdominio (SUBDOMAIN) que quieres usar (ej: casa): " CF_SUBDOMAIN
fi

read -rp "❓ ¿Quieres instalar Cloudflared Tunnel? [s/n]: " INSTALL_TUNNEL
INSTALL_TUNNEL=${INSTALL_TUNNEL,,}

if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  read -rp "🔑 Ingresa tu token del túnel de Cloudflare: " CF_TUNNEL_TOKEN
fi

read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
echo

# ========================
# Descargar plantilla si no existe
# ========================
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  msg_info "Descargando plantilla ${TEMPLATE}..."
  pveam update
  pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)
msg_info "Creando contenedor LXC con ID $CTID..."

pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname $CT_HOSTNAME \
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
# Asignar contraseña root
# ========================
msg_info "Asignando contraseña de root..."
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker dentro del contenedor
# ========================
msg_info "Instalando Docker dentro del contenedor..."
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
if [[ "$INSTALL_DDNS" == "s" ]]; then
  msg_info "Configurando Cloudflare DDNS dentro del contenedor..."
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
  msg_ok "Cloudflare DDNS desplegado correctamente"
fi

# ========================
# Docker: Cloudflared Tunnel
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  msg_info "Desplegando Cloudflared Tunnel..."
  lxc-attach -n $CTID -- bash -c "
    docker run -d --name cloudflared \
      cloudflare/cloudflared:latest tunnel --no-autoupdate run --token ${CF_TUNNEL_TOKEN}
  "
  msg_ok "Cloudflared Tunnel desplegado correctamente"
fi

# ========================
# Final
# ========================
msg_ok "🎉 Contenedor LXC #$CTID desplegado correctamente."
echo -e "[INFO] Puedes acceder con: \033[1;33mpct enter $CTID\033[0m y usar la contraseña de root proporcionada."
