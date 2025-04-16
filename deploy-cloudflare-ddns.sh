#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

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
# Selección de almacenamiento
# ========================
read -rp "🖴 Ingresa el storage de Proxmox a usar [local]: " DETECTED_STORAGE
DETECTED_STORAGE=${DETECTED_STORAGE:-local}

# Verificar si el storage existe
if ! pvesm status | grep -q "^${DETECTED_STORAGE}"; then
  msg_error "❌ El storage '${DETECTED_STORAGE}' no existe en Proxmox"
  read -rp "🖴 Ingresa un storage válido de Proxmox: " DETECTED_STORAGE
  
  # Verificar nuevamente
  if ! pvesm status | grep -q "^${DETECTED_STORAGE}"; then
    msg_error "❌ El storage '${DETECTED_STORAGE}' no existe. Usando 'local' por defecto."
    DETECTED_STORAGE="local"
  fi
fi

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" && ! -f "/var/lib/pve/local/template/cache/${TEMPLATE}" ]]; then
  msg_info "📥 Descargando plantilla Debian 12..."
  pveam update
  if ! pveam download ${DETECTED_STORAGE} ${TEMPLATE}; then
    msg_error "❌ Error al descargar la plantilla. Abortando."
    exit 1
  fi
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)
msg_info "🔨 Creando contenedor LXC #${CTID}..."

if ! pct create $CTID ${DETECTED_STORAGE}:vztmpl/${TEMPLATE} \
  -hostname cloudflare-stack \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1; then
  
  msg_error "❌ Error al crear el contenedor. Abortando."
  exit 1
fi

msg_ok "✅ Contenedor LXC #${CTID} creado correctamente"

# ========================
# Iniciar contenedor
# ========================
msg_info "🚀 Iniciando contenedor..."
if ! pct start $CTID; then
  msg_error "❌ Error al iniciar el contenedor. Abortando."
  exit 1
fi

# Esperar a que el contenedor esté listo
msg_info "⏳ Esperando a que el contenedor esté listo..."
sleep 10

# ========================
# Asignar contraseña root
# ========================
msg_info "🔐 Configurando contraseña de root..."
if ! lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"; then
  msg_error "❌ Error al configurar la contraseña. Continuando de todos modos."
fi

# ========================
# Instalar Docker
# ========================
msg_info "🐳 Instalando Docker..."
if ! lxc-attach -n $CTID -- bash -c "
  apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"; then
  msg_error "❌ Error al instalar Docker. Abortando."
  exit 1
fi

msg_ok "✅ Docker instalado correctamente"

# ========================
# Instalar Cloudflare DDNS
# ========================
if [[ "$INSTALL_DDNS" == "s" ]]; then
  msg_info "🌐 Instalando Cloudflare DDNS..."
  
  if ! lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/ddns && cd /opt/ddns
    
    # Crear archivo de configuración
    cat <<EOF > config.json
{
  \"apiKey\": \"${CF_API_KEY}\",
  \"zone\": \"${CF_ZONE}\",
  \"subdomain\": \"${CF_SUBDOMAIN}\",
  \"proxied\": false
}
EOF
    
    # Crear docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3'
services:
  cloudflare-ddns:
    image: oznu/cloudflare-ddns:latest
    restart: always
    volumes:
      - ./config.json:/app/config.json:ro
EOF
    
    # Iniciar el servicio
    if ! docker compose up -d; then
      echo 'Error al iniciar el servicio Cloudflare DDNS'
      exit 1
    fi
  "; then
    msg_error "❌ Error al configurar Cloudflare DDNS."
  else
    msg_ok "✅ Cloudflare DDNS desplegado correctamente"
  fi
fi

# ========================
# Instalar Cloudflared Tunnel
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  msg_info "🚇 Instalando Cloudflared Tunnel..."
  
  if ! lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/cloudflared && cd /opt/cloudflared
    
    # Crear docker-compose.yml
    cat <<EOF > docker-compose.yml
version: '3'
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: always
    command: tunnel --no-autoupdate run --token \${CF_TUNNEL_TOKEN}
EOF
    
    # Iniciar el servicio
    if ! docker compose up -d; then
      echo 'Error al iniciar el servicio Cloudflared Tunnel'
      exit 1
    fi
  "; then
    msg_error "❌ Error al configurar Cloudflared Tunnel."
  else
    msg_ok "✅ Cloudflared Tunnel desplegado correctamente"
  fi
fi

# ========================
# Crear script de actualización
# ========================
msg_info "🔄 Creando script de actualización..."
if ! lxc-attach -n $CTID -- bash -c "
  cat <<EOF > /usr/local/bin/actualizar-servicios.sh
#!/bin/bash
echo '🔄 Actualizando servicios de Cloudflare...'

if [ -d /opt/ddns ]; then
  echo '🌐 Actualizando Cloudflare DDNS...'
  cd /opt/ddns && docker compose pull && docker compose up -d
fi

if [ -d /opt/cloudflared ]; then
  echo '🚇 Actualizando Cloudflared Tunnel...'
  cd /opt/cloudflared && docker compose pull && docker compose up -d
fi

echo '✅ Actualización completada.'
EOF
  chmod +x /usr/local/bin/actualizar-servicios.sh
"; then
  msg_error "❌ Error al crear script de actualización."
else
  msg_ok "✅ Script de actualización creado correctamente"
fi

# ========================
# Final
# ========================
msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
echo -e "${INFO}${YW} Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste.${CL}"
echo -e "${INFO}${YW} Para actualizar los servicios en el futuro, ejecuta: 'actualizar-servicios.sh'${CL}"

if [[ "$INSTALL_DDNS" == "s" ]]; then
  echo -e "${INFO}${YW} Cloudflare DDNS configurado para: ${CF_SUBDOMAIN}.${CF_ZONE}${CL}"
fi

if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  echo -e "${INFO}${YW} Cloudflared Tunnel desplegado correctamente. Configura tus aplicaciones en el panel de Cloudflare.${CL}"
fi
