#!/usr/bin/env bash

# ========================
# Configuración de logs
# ========================
LOG_FILE="/var/log/cloudflare-stack-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "📝 Iniciando instalación. Log guardado en: $LOG_FILE"

# ========================
# Implementación de funciones necesarias
# ========================
msg_info() {
  echo -e "\e[1;34m[INFO]\e[0m $1"
}

msg_ok() {
  echo -e "\e[1;32m[OK]\e[0m $1"
}

msg_error() {
  echo -e "\e[1;31m[ERROR]\e[0m $1"
  exit 1
}

# ========================
# Función de limpieza en caso de error
# ========================
cleanup() {
  echo "🧹 Error detectado. Limpiando recursos..."
  if [[ -n "$CTID" ]] && pct status $CTID &>/dev/null; then
    echo "🧹 Deteniendo y eliminando contenedor $CTID..."
    pct stop $CTID
    pct destroy $CTID
  fi
  echo "🧹 Limpieza completada. Revisa el log en $LOG_FILE"
  exit 1
}

# Configurar trap para capturar errores
trap cleanup ERR

# ========================
# Verificación de requisitos
# ========================
check_requirements() {
  echo "🔍 Verificando requisitos previos..."
  
  # Verificar que se ejecuta como root
  if [[ $EUID -ne 0 ]]; then
    msg_error "Este script debe ejecutarse como root"
  fi
  
  # Verificar que Proxmox está instalado
  if ! command -v pveversion &> /dev/null; then
    msg_error "Proxmox VE no está instalado o no es accesible"
  fi
  
  # Verificar conectividad a Internet
  if ! ping -c 1 cloudflare.com &> /dev/null; then
    msg_error "No hay conexión a Internet"
  fi
  
  echo "✅ Todos los requisitos verificados correctamente"
}

# ========================
# Función para verificar resultado de comandos
# ========================
check_command() {
  if [ $? -ne 0 ]; then
    msg_error "Falló el comando: $1"
  fi
}

# ========================
# Configuración de la aplicación
# ========================
APP="Cloudflare-DDNS / Cloudflared Tunnel"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

echo "🚀 Instalando $APP"
echo "===================="
echo "CPU: $var_cpu"
echo "RAM: $var_ram MB"
echo "Disco: $var_disk GB"
echo "OS: $var_os $var_version"
echo "Unprivileged: $var_unprivileged"
echo "===================="

# ========================
# Verificar requisitos
# ========================
check_requirements

# ========================
# Detectar almacenamiento compatible
# ========================
echo "🔍 Detectando almacenamiento compatible con contenedores LXC..."

# Intentar detectar automáticamente un almacenamiento compatible
DETECTED_STORAGE=$(pvesm status | grep -E 'active.*yes' | grep -E 'content.*rootdir' | head -n1 | awk '{print $1}')

if [[ -z "$DETECTED_STORAGE" ]]; then
  echo "⚠️ No se detectó automáticamente un almacenamiento compatible con contenedores."
  echo "Mostrando almacenamientos disponibles:"
  pvesm status
  
  read -rp "🔢 Ingresa el nombre del almacenamiento a usar: " DETECTED_STORAGE
  
  # Verificar si el almacenamiento existe
  if ! pvesm status -storage $DETECTED_STORAGE &>/dev/null; then
    msg_error "El almacenamiento '$DETECTED_STORAGE' no existe"
  fi
  
  # Verificar si el almacenamiento soporta contenedores
  if ! pvesm status -storage $DETECTED_STORAGE | grep -q "content.*rootdir"; then
    echo "⚠️ El almacenamiento '$DETECTED_STORAGE' podría no soportar contenedores."
    read -rp "¿Deseas continuar de todos modos? [s/n]: " CONTINUE
    if [[ "${CONTINUE,,}" != "s" ]]; then
      echo "Operación cancelada por el usuario."
      exit 0
    fi
  fi
fi

echo "💾 Usando almacenamiento: $DETECTED_STORAGE"

# ========================
# Preguntas condicionales con validación
# ========================
read -rp "❓ ¿Quieres instalar Cloudflare DDNS? [s/n]: " INSTALL_DDNS
INSTALL_DDNS=${INSTALL_DDNS,,} # minúsculas

if [[ "$INSTALL_DDNS" == "s" ]]; then
  # Validación de API Key
  while true; do
    read -rp "🔐 Ingresa tu API Key de Cloudflare: " CF_API_KEY
    if [[ -z "$CF_API_KEY" || ${#CF_API_KEY} -lt 30 ]]; then
      echo "⚠️ La API Key parece demasiado corta. Por favor verifica."
    else
      break
    fi
  done
  
  # Validación de dominio
  while true; do
    read -rp "🌐 Ingresa tu dominio (ZONE) en Cloudflare (ej: midominio.com): " CF_ZONE
    if [[ ! "$CF_ZONE" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      echo "⚠️ El formato del dominio no parece válido. Ejemplo correcto: midominio.com"
    else
      break
    fi
  done
  
  # Preguntar si desea usar un subdominio
  read -rp "❓ ¿Quieres configurar un subdominio específico? [s/n]: " USE_SUBDOMAIN
  USE_SUBDOMAIN=${USE_SUBDOMAIN,,}
  
  if [[ "$USE_SUBDOMAIN" == "s" ]]; then
    # Validación de subdominio
    while true; do
      read -rp "🧩 Ingresa el subdominio (SUBDOMAIN) que quieres usar (ej: casa): " CF_SUBDOMAIN
      if [[ -z "$CF_SUBDOMAIN" || "$CF_SUBDOMAIN" =~ [^a-zA-Z0-9-] ]]; then
        echo "⚠️ El subdominio solo debe contener letras, números y guiones."
      else
        break
      fi
    done
  else
    # Si no se usa subdominio, dejarlo vacío
    CF_SUBDOMAIN=""
    echo "ℹ️ Se actualizará el dominio principal sin subdominio."
  fi
fi

read -rp "❓ ¿Quieres instalar Cloudflared Tunnel? [s/n]: " INSTALL_TUNNEL
INSTALL_TUNNEL=${INSTALL_TUNNEL,,}

if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  # Validación de token
  while true; do
    read -rp "🔑 Ingresa tu token del túnel de Cloudflare: " CF_TUNNEL_TOKEN
    if [[ -z "$CF_TUNNEL_TOKEN" || ${#CF_TUNNEL_TOKEN} -lt 30 ]]; then
      echo "⚠️ El token parece demasiado corto. Por favor verifica."
    else
      break
    fi
  done
fi

# Validación de contraseña
while true; do
  read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
  echo
  if [[ -z "$ROOT_PASSWORD" || ${#ROOT_PASSWORD} -lt 8 ]]; then
    echo "⚠️ La contraseña debe tener al menos 8 caracteres."
  else
    read -rsp "🔐 Confirma la contraseña: " ROOT_PASSWORD_CONFIRM
    echo
    if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
      echo "⚠️ Las contraseñas no coinciden."
    else
      break
    fi
  fi
done

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
echo "🔍 Verificando si existe la plantilla $TEMPLATE..."
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" && ! -f "/var/lib/pve/local/template/cache/${TEMPLATE}" ]]; then
  echo "📥 Descargando plantilla $TEMPLATE..."
  pveam update
  check_command "pveam update"
  pveam download ${DETECTED_STORAGE} ${TEMPLATE}
  check_command "pveam download ${DETECTED_STORAGE} ${TEMPLATE}"
fi

# ========================
# Crear contenedor automáticamente
# ========================
echo "🚀 Creando contenedor LXC..."
CTID=$(pvesh get /cluster/nextid)
echo "🆔 ID del contenedor: $CTID"

echo "⚙️ Configurando contenedor..."
pct create $CTID ${DETECTED_STORAGE}:vztmpl/${TEMPLATE} \
  -hostname cloudflare-stack \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1
check_command "Creación del contenedor"

echo "▶️ Iniciando contenedor..."
pct start $CTID
check_command "Inicio del contenedor"
echo "⏳ Esperando a que el contenedor esté listo..."
sleep 5

# ========================
# Asignar contraseña root
# ========================
echo "🔐 Configurando contraseña de root..."
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"
check_command "Configuración de contraseña"

# ========================
# Instalar Docker
# ========================
echo "🐳 Instalando Docker..."
lxc-attach -n $CTID -- bash -c "
  apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
  check_command() { if [ \$? -ne 0 ]; then echo \"Error: \$1\"; exit 1; fi; }
  
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  check_command 'Descarga de clave GPG de Docker'
  
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  check_command 'Configuración de repositorio Docker'
  
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  check_command 'Instalación de Docker'
  
  # Verificar que Docker está funcionando
  docker --version
  check_command 'Verificación de Docker'
"
check_command "Instalación de Docker"

# ========================
# Instalar Cloudflare DDNS
# ========================
if [[ "$INSTALL_DDNS" == "s" ]]; then
  echo "🌐 Instalando Cloudflare DDNS..."
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
$(if [[ -n "$CF_SUBDOMAIN" ]]; then echo "      - SUBDOMAIN=${CF_SUBDOMAIN}"; fi)
      - PROXIED=false
EOF
    docker compose up -d
    if [ \$? -ne 0 ]; then echo \"Error al iniciar Cloudflare DDNS\"; exit 1; fi
    
    # Verificar que el contenedor está funcionando
    if docker ps | grep -q cloudflare-ddns; then
      echo \"✅ Cloudflare DDNS iniciado correctamente\"
    else
      echo \"❌ Error: Cloudflare DDNS no se inició correctamente\"
      exit 1
    fi
  "
  check_command "Instalación de Cloudflare DDNS"
  
  # Mensaje informativo sobre la configuración
  if [[ -n "$CF_SUBDOMAIN" ]]; then
    msg_ok "Cloudflare DDNS desplegado correctamente para ${CF_SUBDOMAIN}.${CF_ZONE}"
  else
    msg_ok "Cloudflare DDNS desplegado correctamente para ${CF_ZONE}"
  fi
fi

# ========================
# Instalar Cloudflared Tunnel
# ========================
if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  echo "🚇 Instalando Cloudflared Tunnel..."
  lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/cloudflared && cd /opt/cloudflared
    cat <<EOF > docker-compose.yml
version: '3'
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: always
    command: tunnel --no-autoupdate run --token ${CF_TUNNEL_TOKEN}
EOF
    docker compose up -d
    if [ \$? -ne 0 ]; then echo \"Error al iniciar Cloudflared Tunnel\"; exit 1; fi
    
    # Verificar que el contenedor está funcionando
    if docker ps | grep -q cloudflared; then
      echo \"✅ Cloudflared Tunnel iniciado correctamente\"
    else
      echo \"❌ Error: Cloudflared Tunnel no se inició correctamente\"
      exit 1
    fi
  "
  check_command "Instalación de Cloudflared Tunnel"
  msg_ok "Cloudflared Tunnel desplegado correctamente"
fi

# ========================
# Guardar configuración
# ========================
echo "💾 Guardando configuración..."
CONFIG_FILE="/root/cloudflare-stack-config-$CTID.sh"
cat <<EOF > "$CONFIG_FILE"
#!/bin/bash
# Configuración de Cloudflare Stack
# Generado el $(date)

CTID=$CTID
EOF

if [[ "$INSTALL_DDNS" == "s" ]]; then
  cat <<EOF >> "$CONFIG_FILE"
DDNS_INSTALLED=true
CF_ZONE=$CF_ZONE
$(if [[ -n "$CF_SUBDOMAIN" ]]; then echo "CF_SUBDOMAIN=$CF_SUBDOMAIN"; fi)
# La API Key no se guarda por seguridad
EOF
fi

if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  cat <<EOF >> "$CONFIG_FILE"
TUNNEL_INSTALLED=true
# El token no se guarda por seguridad
EOF
fi

chmod 600 "$CONFIG_FILE"
echo "📝 Configuración guardada en $CONFIG_FILE"

# ========================
# Verificación final de servicios
# ========================
echo "🔍 Verificando servicios..."
if [[ "$INSTALL_DDNS" == "s" ]]; then
  lxc-attach -n $CTID -- bash -c "
    if docker ps | grep -q cloudflare-ddns; then
      echo '✅ Servicio DDNS funcionando correctamente'
    else
      echo '❌ Error: Servicio DDNS no está funcionando'
      exit 1
    fi
  "
fi

if [[ "$INSTALL_TUNNEL" == "s" ]]; then
  lxc-attach -n $CTID -- bash -c "
    if docker ps | grep -q cloudflared; then
      echo '✅ Servicio Cloudflared funcionando correctamente'
    else
      echo '❌ Error: Servicio Cloudflared no está funcionando'
      exit 1
    fi
  "
fi

# ========================
# Final
# ========================
msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
echo -e "\e[1;33m[INFO]\e[0m Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste."
echo -e "\e[1;33m[INFO]\e[0m Log de instalación guardado en: $LOG_FILE"

# Desactivar trap al finalizar correctamente
trap - ERR
