Cloudflare Stack (DDNS + Tunnel Zero Trust)

🌩️ ¿Qué incluye este stack?
Este proyecto despliega en Proxmox un contenedor LXC Debian súper liviano con Docker y dos servicios:

oznu/cloudflare-ddns: actualiza automáticamente la IP pública de tu dominio/subdominio.
cloudflared: crea túneles seguros a través de Cloudflare Tunnel (ideal para acceder remotamente a servicios internos).

** 🔐 Crear API Token para DDNS **

Accede al panel de Cloudflare.
1. Haz clic en tu ícono de perfil (arriba a la derecha).
2. Selecciona "Mi perfil".
3. Ve a "Tokens de API" (menú izquierdo).
4. Haz clic en "Crear token".
5. Baja hasta la plantilla "Editar zona DNS" y haz clic en "Usar plantilla".
6. En Permisos, configura lo siguiente:

ZONA → CONFIGURACIÓN DE ZONA → LEER
ZONA → ZONA → LEER
ZONA → DNS → EDITAR

7. En "Recursos de zona", selecciona:

INCLUIR → TODAS LAS ZONAS

8. Haz clic en "Continuar hasta resumen", revisa y crea el token.
9. Copia el token y guárdalo en un lugar seguro.

** 🔐 Crear API Token para Cloudflared Tunnel **

1. Desde el panel de Cloudflare, ve a Zero Trust Dashboard:
https://dash.teams.cloudflare.com/
2. En el menú lateral ve a Access → Tunnels.
3. Crea un túnel nuevo, colocale el nombre que desees.
4. En configurar, ve a la pestaña docker y copia y guarda el conector en un lugar seguro.

Ejemplo de conector:
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiYTNmNDZiYWIzMDccNTRlODE2ODg0Zjc0YmIwZjFkZmYiLCJ0IjoiZGNmMDBkNLEtZDU0ZC00MjFjLTkxZTAtOTNlM2VkNTU4NTUyIiwicyI69k1UbGxaakkwTWpBdFpqVTRaUzAwWkRreUxUaGlaR0l0WVdSaU16ZzFaV1U033RRNSJ9

** ⚙️ 3. Desplegar el stack en tu nodo Proxmox **

1. Ejecuta este comando desde la shell del nodo:

    bash <(curl -s https://raw.githubusercontent.com/esweb-es/proxmox-cloudflare-ddns/main/deploy-cloudflare-ddns.sh)
    
2. Este script creará un contenedor LXC Debian muy ligero, instalará Docker y lanzará los contenedores de:

oznu/cloudflare-ddns
ghcr.io/cloudflare/cloudflared

📂 Estructura esperada en el contenedor:

/opt/ddns/docker-compose.yml   ← Configuración de oznu/cloudflare-ddns
/opt/cloudflared/docker-compose.yml   ← Configuración del túnel 
