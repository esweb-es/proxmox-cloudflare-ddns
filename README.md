# 🌩️ Cloudflare Stack (DDNS + Tunnel Zero Trust)

Este proyecto despliega en **Proxmox** un contenedor **LXC Debian minimalista** con **Docker** preinstalado y dos servicios de Cloudflare:

- [`oznu/cloudflare-ddns`](https://hub.docker.com/r/oznu/cloudflare-ddns): actualiza automáticamente la IP pública de tu dominio/subdominio.
- [`cloudflare/cloudflared`](https://hub.docker.com/r/cloudflare/cloudflared): crea túneles seguros con Cloudflare Tunnel (ideal para acceder remotamente a servicios internos).

---

## 🔐 1. Crear API Token para Cloudflare DDNS

1. Accede al [panel de Cloudflare](https://dash.cloudflare.com).
2. Haz clic en tu ícono de perfil (arriba a la derecha) → **"Mi perfil"**.
3. Ve a la pestaña **"Tokens de API"**.
4. Haz clic en **"Crear token"**.
5. Desplázate hasta la plantilla **"Editar zona DNS"** y haz clic en **"Usar plantilla"**.
6. En la sección **Permisos**, configura lo siguiente:

ZONA → CONFIGURACIÓN DE ZONA → LEER
ZONA → ZONA → LEER
ZONA → DNS → EDITAR


7. En **"Recursos de zona"**, selecciona:
8. Haz clic en **"Continuar hasta resumen"**, revisa y crea el token.
9. **Copia el token** y guárdalo en un lugar seguro.

---

## 🛡️ 2. Crear Token para Cloudflared Tunnel

1. Accede al [Cloudflare Zero Trust Dashboard](https://dash.teams.cloudflare.com/).
2. En el menú lateral, ve a **Access → Tunnels**.
3. Crea un túnel nuevo y asígnale el nombre que desees.
4. En la sección de configuración, selecciona la pestaña **Docker**.
5. **Copia el comando que aparece**. Contiene el token de conexión.

**Ejemplo:**

```bash
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiYTNmlDZiYWIzMDczNTRrODE2ODg0Zqc0YmIwZjFkZrYsLCJ0IjoiYWJkN2ZiZjAtMGFlYS00Yjg1LWJkZWMtNjNlMzEzYjg4MmVjIiwicyInIk4yUTVNR00wTnpFdFpEZzFZeTAwT0dOaUxXSmhZell0TVRNMVlrUXlOVE5rlTJNeCJ9
```

6. Guarda ese token de forma segura. Lo necesitarás durante la instalación.

## ⚙️ 3. Desplegar el Stack en Proxmox

### ✅ Requisitos

- Nodo Proxmox con acceso a Internet.
- Al menos **2 GB** de espacio libre en el almacenamiento `local`.

### 🧪 Instalación automática

Ejecuta el siguiente comando desde la **shell del nodo Proxmox**:

```bash
bash <(curl -s https://raw.githubusercontent.com/esweb-es/proxmox-cloudflare-ddns/main/deploy-cloudflare-ddns.sh)
```

Este script:

- Crea un contenedor LXC Debian liviano.
- Instala Docker y docker-compose plugin.
- Lanza los siguientes servicios según tu elección:
  - `oznu/cloudflare-ddns`
  - `cloudflare/cloudflared`

---

## 📂 Estructura esperada en el contenedor

```bash
/opt/ddns/docker-compose.yml          # Configuración del servicio oznu/cloudflare-ddns
/opt/cloudflared/docker-compose.yml   # (Opcional) Configuración del túnel si deseas adaptarlo a docker-compose
```

> ☝️ Nota: por defecto, `cloudflared` se ejecuta con `docker run`, pero puedes convertirlo fácilmente a `docker-compose` si prefieres mantener todo organizado.

---

## 🧾 Créditos y Licencia

- Proyecto mantenido por [@esweb-es](https://github.com/esweb-es)
- Basado en imágenes oficiales de:
  - [Cloudflare](https://developers.cloudflare.com/)
  - [oznu/cloudflare-ddns](https://hub.docker.com/r/oznu/cloudflare-ddns)
