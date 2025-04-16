#!/bin/bash

# ================================================
# CONFIGURACIÓN INICIAL
# ================================================
set -euo pipefail

read -p "🆔 Ingresa el ID del contenedor LXC: " CT_ID
read -p "💾 Almacenamiento (local o local-lvm): " STORAGE
read -p "🌐 ¿Usar IP estática? (s/n): " STATIC_IP

if [[ "$STATIC_IP" == "s" ]]; then
    read -p "📍 IP estática (ej: 192.168.1.100/24): " IP
    read -p "🚪 Gateway (ej: 192.168.1.1): " GATEWAY
else
    IP="dhcp"
    GATEWAY=""
fi

read -p "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " -s ROOT_PASS
echo

TEMPLATE_NAME="debian-12-standard_12.2-1_amd64.tar.zst"

# ================================================
# VERIFICAR Y DESCARGAR LA PLANTILLA SI FALTA
# ================================================
echo "🔍 Verificando plantilla $TEMPLATE_NAME en $STORAGE..."
if ! ls "/var/lib/pve/local/template/cache/$TEMPLATE_NAME" &>/dev/null && ! ls "/var/lib/vz/template/cache/$TEMPLATE_NAME" &>/dev/null; then
    echo "📥 Descargando plantilla..."
    pveam update
    pveam download "$STORAGE" "$TEMPLATE_NAME"
else
    echo "✅ Plantilla ya disponible."
fi

# ================================================
# CREACIÓN DEL CONTENEDOR
# ================================================
echo "⚙️  Creando contenedor..."
pct create "$CT_ID" \
    /var/lib/pve/template/cache/$TEMPLATE_NAME \
    -storage "$STORAGE" \
    -hostname wg-easy \
    -memory 512 \
    -cores 1 \
    -net0 name=eth0,bridge=vmbr0,ip=$IP$( [ "$IP" != "dhcp" ] && echo ",gw=$GATEWAY" ) \
    -rootfs "$STORAGE":4G \
    -password "$ROOT_PASS" \
    -features nesting=1 \
    -unprivileged 1

# ================================================
# INICIAR EL CONTENEDOR
# ================================================
echo "🚀 Iniciando contenedor..."
pct start "$CT_ID"
echo "✅ Contenedor $CT_ID creado e iniciado con éxito."
