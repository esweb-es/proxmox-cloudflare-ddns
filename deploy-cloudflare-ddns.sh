#!/usr/bin/env bash
set -euo pipefail

# ========================
# Funciones locales
# ========================
header_info() {
  echo -e "\n\e[1;34m==============================\e[0m"
  echo -e "\e[1;34m  $1\e[0m"
  echo -e "\e[1;34m==============================\e[0m"
}

msg_ok() {
  echo -e "\e[1;32m[OK]\e[0m $1"
}

# Colores informativos
INFO="\e[36m"
YW="\e[33m"
CL="\e[0m"

# ========================
# Variables principales
# ========================
APP="Cloudflare-DDNS / Cloudflared Tunnel"
var_tags="docker ddns cloudflare cloudflared"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"

# ========================
# Preguntas condicionales
# ========================
read -rp "❓ ¿Quieres instalar Cloudflare DDNS? [s/n]: " INSTALL_DDNS
INSTALL_DDNS=${INSTALL_DDNS,,} # minúsculas

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
  -hostname cloudflare-stack \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1 \
  -onboot 1

pct start $CTID
sleep 5

# ========================
# Asignar contraseña root
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================
lxc-attach -n $CTID -- bash -c "
  apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Instalar Cloudflare DDNS
# ========================
if [[ "$INSTALL_DDNS" == "s" ]]; then
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
  msg_ok "✅ Cloudflare DDNS desplegado correctamente"
fi

# ========================
# Instalar Cloudflared Tunnel
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  lxc-attach -n $CTID -- bash -c "
    docker run -d --name cloudflared \
      cloudflare/cloudflared:latest tunnel --no-autoupdate run --token ${CF_TUNNEL_TOKEN}
  "
  msg_ok "✅ Cloudflared Tunnel desplegado correctamente"
fi

# ========================
# Final
# ========================
msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
echo -e "${INFO}${YW} Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste.${CL}"
