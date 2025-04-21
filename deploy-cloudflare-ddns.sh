#!/usr/bin/env bash

# ========================
# FUNCIONES LOCALES
# ========================
header_info() { echo -e "\n🧠 $1\n"; }
variables() { :; }
color() { :; }
catch_errors() { :; }
msg_ok() { echo -e "✅ $1"; }

# ========================
# CONFIGURACIÓN INICIAL
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
variables
color
catch_errors

# ========================
# PREGUNTAS INTERACTIVAS
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
# CONFIGURACIÓN DE PLANTILLA Y ALMACENAMIENTO
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"

# Asegurar que la plantilla esté disponible
if [[ ! -f "/var/lib/pve/local/template/cache/${TEMPLATE}" ]]; then
  echo "⬇️ Descargando plantilla Debian 12..."
  pveam update
  pveam download $TEMPLATE_STORAGE $TEMPLATE
fi

# ========================
# CREAR CONTENEDOR
# ========================
CTID=$(pvesh get /cluster/nextid)
echo "📦 Creando contenedor LXC ID #$CTID..."

pct create $CTID ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE} \
  -rootfs ${ROOTFS_STORAGE}:${var_disk} \
  -hostname cloudflare-stack \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# ========================
# CONFIGURAR CONTRASEÑA ROOT
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# INSTALAR DOCKER
# ========================
echo "🐳 Instalando Docker dentro del contenedor..."
lxc-attach -n $CTID -- bash -c "
apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# DESPLEGAR CLOUDFLARE DDNS
# ========================
if [[ "$INSTALL_DDNS" == "s" ]]; then
  echo "🚀 Desplegando Cloudflare DDNS..."
  lxc-attach -n $CTID -- bash -c '
    mkdir -p /opt/ddns && cd /opt/ddns
    cat <<EOF > docker-compose.yml
services:
  cloudflare-ddns:
    image: oznu/cloudflare-ddns:latest
    restart: always
    environment:
      - API_KEY='"${CF_API_KEY}"'
      - ZONE='"${CF_ZONE}"'
      - SUBDOMAIN='"${CF_SUBDOMAIN}"'
      - PROXIED=false
EOF
    docker compose up -d
  '
  msg_ok "Cloudflare DDNS desplegado correctamente"
fi

# ========================
# DESPLEGAR CLOUDFLARED TUNNEL
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  echo "🚀 Desplegando Cloudflared Tunnel..."
  lxc-attach -n $CTID -- bash -c '
    mkdir -p /opt/cloudflare && cd /opt/cloudflare
    cat <<EOF > docker-compose.yml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: always
    command: tunnel --no-autoupdate run --token '"${CF_TUNNEL_TOKEN}"'
EOF
    docker compose up -d
  '
  msg_ok "Cloudflared Tunnel desplegado correctamente"
fi

# ========================
# FINAL
# ========================
msg_ok "🎉 Contenedor LXC #$CTID desplegado correctamente."
echo -e "\nPuedes acceder con: \e[1mpct enter $CTID\e[0m y usar la contraseña de root que proporcionaste."
