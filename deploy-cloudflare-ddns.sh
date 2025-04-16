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

# ========================
# Variables
# ========================
APP="Cloudflare DDNS + Tunnel (Alpine)"
TEMPLATE="alpine-3.19-standard_20240106_amd64.tar.xz"
ROOT_PASSWORD=""

header_info "$APP"

# ========================
# Preguntas condicionales
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
  pveam update
  pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor LXC Alpine
# ========================
CTID=$(pvesh get /cluster/nextid)

pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname cloudflare-stack \
  -rootfs local:2 \
  -memory 512 \
  -cores 1 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -nameserver 1.1.1.1 \
  -features nesting=1 \
  -unprivileged 1 \
  -onboot 1

pct start $CTID
sleep 3

# ========================
# Establecer contraseña root
# ========================
lxc-attach -n $CTID -- sh -c "echo root:$ROOT_PASSWORD | chpasswd"

# ========================
# Instalar Docker
# ========================
lxc-attach -n $CTID -- sh -c "
  apk update && apk add docker
  rc-update add docker boot
  service docker start
"

# ========================
# Lanzar DDNS
# ========================
if [[ "$INSTALL_DDNS" == "s" ]]; then
  lxc-attach -n $CTID -- sh -c "
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
# Lanzar Tunnel
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  lxc-attach -n $CTID -- sh -c "
    docker run -d --name cloudflared \
      cloudflare/cloudflared:latest tunnel --no-autoupdate run --token ${CF_TUNNEL_TOKEN}
  "
  msg_ok "✅ Cloudflared Tunnel desplegado correctamente"
fi

# ========================
# Final
# ========================
msg_ok "🎉 Contenedor Alpine LXC #$CTID desplegado correctamente."
echo -e "\nℹ️ Puedes acceder con: pct enter $CTID"
