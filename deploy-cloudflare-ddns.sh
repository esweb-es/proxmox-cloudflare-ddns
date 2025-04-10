#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
APP="WG-Easy (WireGuard UI)"
var_tags="docker wireguard vpn wg-easy"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

var_wg_port="51820"
var_wg_clients_subnet="10.8.0.0/24"
var_wg_dns="1.1.1.1"

header_info "$APP"
variables
color
catch_errors

# ========================
# Preguntas condicionales
# ========================
read -rp "❓ ¿Quieres instalar WG-Easy? [s/n]: " INSTALL_WGEASY
INSTALL_WGEASY=${INSTALL_WGEASY,,}

if [[ "$INSTALL_WGEASY" == "s" ]]; then
  read -rp "👂 Puerto de escucha de WireGuard [${var_wg_port}]: " WG_PORT
  [[ -z "$WG_PORT" ]] && WG_PORT="${var_wg_port}"

  read -rp "🌐 Subred para clientes WireGuard [${var_wg_clients_subnet}]: " WG_CLIENTS_SUBNET
  [[ -z "$WG_CLIENTS_SUBNET" ]] && WG_CLIENTS_SUBNET="${var_wg_clients_subnet}"

  read -rp "⚙️ Servidores DNS para los clientes WireGuard (separados por comas) [${var_wg_dns}]: " WG_DNS
  [[ -z "$WG_DNS" ]] && WG_DNS="${var_wg_dns}"

  read -rp "👤 Nombre de usuario para la interfaz web de WG-Easy (opcional): " WG_WEB_USERNAME
  read -rsp "🔑 Contraseña para la interfaz web de WG-Easy (opcional): " WG_WEB_PASSWORD
  echo
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
  -hostname wg-easy \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

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
# Instalar WG-Easy
# ========================
if [[ "$INSTALL_WGEASY" == "s" ]]; then
  lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/wg-easy && cd /opt/wg-easy
    cat <<EOF > docker-compose.yml
version: '3'
services:
  wg-easy:
    image: weejewel/wg-easy:latest
    container_name: wg-easy
    environment:
      - WG_HOST=\$(ip -4 addr show eth0 | grep -Po 'inet \K[\d.]+')
      - WG_PORT=${WG_PORT}
      - WG_CLIENT_SUBNET=${WG_CLIENTS_SUBNET}
      - WG_DNS=${WG_DNS}
      $( [[ -n "$WG_WEB_USERNAME" ]] && echo "- WG_PASSWORD=$WG_WEB_PASSWORD" )
      $( [[ -n "$WG_WEB_USERNAME" ]] && echo "- WG_USERNAME=$WG_WEB_USERNAME" )
    ports:
      - ${WG_PORT}/udp
      - 51821:51821/tcp # Puerto para la interfaz web (opcional)
    volumes:
      - /opt/wg-easy/config:/etc/wireguard
    restart: unless-stopped
EOF
    docker compose up -d
  "
  msg_ok "✅ WG-Easy desplegado correctamente. Accede a la interfaz web en http://<IP_del_Contenedor>:51821"
fi

# ========================
# Final
# ========================
msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
echo -e "${INFO}${YW} Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste.${CL}"
