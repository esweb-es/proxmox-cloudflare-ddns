#!/usr/bin/env bash

# ========================
# Funciones de utilidad
# ========================
function msg_info() {
  local msg="$1"
  echo -e "\e[1;34m${msg}\e[0m"
}

function msg_ok() {
  local msg="$1"
  echo -e "\e[1;32m${msg}\e[0m"
}

function msg_error() {
  local msg="$1"
  echo -e "\e[1;31m${msg}\e[0m"
}

function catch_errors() {
  set -e
  trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
  trap 'if [ $? -ne 0 ]; then echo -e "\e[1;31mERROR: El comando \"${last_command}\" falló con código de salida $?.\e[0m"; fi' EXIT
}

# ========================
# Configuración inicial
# ========================
APP="Cloudflare-DDNS / Cloudflared Tunnel"
var_cpu="1"
var_ram="512"
var_disk="2"
var_unprivileged="1"

# Iniciar captura de errores
catch_errors

# ========================
# Cabecera
# ========================
clear
echo -e "\e[1;33m"
echo "  ___ _                 _  __ _                 "
echo " / __| |___  _  _ __| |/ _| |__ _ _ _ ___    "
echo "| (__| / _ \| || |/ _  |  _| / _\` | '_/ -_)   "
echo " \___|_\___/ \_,_|___|_|_| |_\__,_|_| \___|   "
echo "                                              "
echo -e "\e[1;32mInstalador de Cloudflare DDNS y Cloudflared Tunnel\e[0m"
echo -e "\e[1;34m--------------------------------------------\e[0m"
echo ""

# ========================
# Verificar si es root
# ========================
if [ "$(id -u)" -ne 0 ]; then
  msg_error "❌ Este script debe ejecutarse como root"
  exit 1
fi

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
if ! pvesm status 2>/dev/null | grep -q "^${DETECTED_STORAGE}"; then
  msg_error "❌ El storage '${DETECTED_STORAGE}' no existe en Proxmox o el comando pvesm no está disponible"
  read -rp "🖴 Ingresa un storage válido de Proxmox (o presiona Enter para usar 'local'): " DETECTED_STORAGE
  DETECTED_STORAGE=${DETECTED_STORAGE:-local}
fi

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"
TEMPLATE_PATH_ALT="/var/lib/pve/local/template/cache/${TEMPLATE}"

if [[ ! -f "$TEMPLATE_PATH" && ! -f "$TEMPLATE_PATH_ALT" ]]; then
  msg_info "📥 Descargando plantilla Debian 12..."
  if command -v pveam >/dev/null 2>&1; then
    pveam update
    if ! pveam download ${DETECTED_STORAGE} ${TEMPLATE}; then
      msg_error "❌ Error al descargar la plantilla. Abortando."
      exit 1
    fi
  else
    msg_error "❌ El comando pveam no está disponible. Verifica que estás en un servidor Proxmox."
    exit 1
  fi
fi

# ========================
# Crear contenedor automáticamente
# ========================
if command -v pvesh >/dev/null 2>&1; then
  CTID=$(pvesh get /cluster/nextid)
else
  msg_error "❌ El comando pvesh no está disponible. Verifica que estás en un servidor Proxmox."
  read -rp "🔢 Ingresa manualmente el ID del contenedor a crear: " CTID
  if [[ -z "$CTID" ]]; then
    msg_error "❌ No se proporcionó un ID de contenedor. Abortando."
    exit 1
  fi
fi

msg_info "🔨 Creando contenedor LXC #${CTID}..."

if command -v pct >/dev/null 2>&1; then
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
else
  msg_error "❌ El comando pct no está disponible. Verifica que estás en un servidor Proxmox."
  exit 1
fi

msg_ok "✅ Contenedor LXC #${CTID} creado correctamente"

# El resto del script continúa igual...
