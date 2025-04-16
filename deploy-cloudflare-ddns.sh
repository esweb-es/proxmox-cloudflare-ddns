#!/bin/bash

# ================================================
# Configuración inicial
# ================================================
set -euo pipefail

# ================================================
# Variables de configuración
# ================================================
CT_ID=101
HOSTNAME="wg-easy"
STORAGE="local"
TEMPLATE="debian-12-standard_12.2-1_amd64.tar.zst"
MEMORY=512
DISK_SIZE=4G
BRIDGE="vmbr0"
IP="dhcp"  # o puedes usar "192.168.1.100/24"
GATEWAY="192.168.1.1"  # solo si usas IP estática

# ================================================
# Verificar si la plantilla existe y descargarla si no
# ================================================
echo "🔍 Verificando si la plantilla '$TEMPLATE' está disponible en '$STORAGE'..."
if ! pct templates | grep -q "$TEMPLATE"; then
    echo "📥 Plantilla no encontrada. Descargando..."
    pveam download "$STORAGE" "$TEMPLATE"
    echo "✅ Plantilla descargada con éxito."
else
    echo "✅ Plantilla ya disponible en '$STORAGE'."
fi

# ================================================
# Crear el contenedor LXC
# ================================================
echo "⚙️  Creando contenedor LXC con ID $CT_ID..."
pct create "$CT_ID" "/var/lib/vz/template/cache/$TEMPLATE" \
  -hostname "$HOSTNAME" \
  -storage "$STORAGE" \
  -memory "$MEMORY" \
  -rootfs "${STORAGE}:${DISK_SIZE}" \
  -net0 name=eth0,bridge=${BRIDGE},ip=${IP}$( [ "$IP" != "dhcp" ] && echo ",gw=${GATEWAY}" ) \
  -features nesting=1 \
  -unprivileged 1

echo "✅ Contenedor creado exitosamente."

# ================================================
# Iniciar el contenedor
# ================================================
pct start "$CT_ID"
echo "🚀 Contenedor iniciado. Puedes acceder con: pct enter $CT_ID"
