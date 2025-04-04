#!/usr/bin/env bash

APP="Cloudflared Tunnel"
CTID=$(pvesh get /cluster/nextid)
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
STORAGE="local-lvm"
RAM="128"
DISK="1"
CPU="1"

read -rsp "🔑 Contraseña para root del contenedor: " ROOT_PASSWORD
echo

# Descargar plantilla si no está
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  pveam update
  pveam download local ${TEMPLATE}
fi

# Crear contenedor
pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname cloudflared \
  -storage $STORAGE \
  -rootfs ${STORAGE}:${DISK} \
  -memory $RAM \
  -cores $CPU \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 1 \
  -features nesting=1

pct start $CTID
until pct status $CTID | grep -q "running"; do sleep 1; done

# Configurar contenedor: instalar cloudflared
lxc-attach -n $CTID -- bash -c "
  echo 'root:$ROOT_PASSWORD' | chpasswd
  apt update && apt install -y curl
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
  dpkg -i cloudflared.deb
  rm cloudflared.deb
"

echo -e "\n✅ Cloudflared instalado en LXC #$CTID"
echo -e "👉 Accede con: pct enter $CTID"
echo -e "⚙️ Luego ejecuta: cloudflared tunnel login"
