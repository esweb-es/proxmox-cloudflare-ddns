#!/usr/bin/env bash

# ========================
# Funciones de Proxmox Helpers
# ========================
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Cloudflare-DDNS"
var_tags="docker ddns cloudflare"
var_cpu="1"
var_ram="128"
var_disk="1"
var_os="debian"
var_version="12"
var_unprivileged="1"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
DETECTED_STORAGE="local-lvm"

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
read -rsp "🔑 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD"
echo

# Validación
if [[ -z "$CF_API_KEY" || -z "$CF_ZONE" || -z "$CF_SUBDOMAIN" || -z "$ROOT_PASSWORD" ]]; then
  echo -e "\n❌ Todos los campos son obligatorios. Abortando."
  exit 1
fi

# ========================
# Descargar plantilla si no existe
# ========================
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  pveam update
  pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)

if [[ -z "$CTID" ]]; then
  echo "❌ No se pudo obtener un CTID válido. Abortando."
  exit 1
fi

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

# ========================
# Esperar a que el contenedor arranque
# ========================
echo "⏳ Esperando que el contenedor #$CTID inicie..."
until pct status $CTID | grep -q "status: running"; do
  sleep 1
done

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
echo -e "${INFO}${YW} Puedes acceder al contenedor con:\n${CL}pct enter $CTID"
echo -e "${INFO}${YW} Usa la contraseña que ingresaste para el usuario root.${CL}"
