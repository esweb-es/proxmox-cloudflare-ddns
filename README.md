Para crear un token de API de Cloudflare para DDNS, puedes seguir estos pasos: 

1: Entrar al panel de Cloudflare.
2: Hacer clic en el menú desplegable del perfil.
3: Seleccionar "Mi perfil".
4: Hacer clic en "Tokens de API" en el menú de navegación izquierdo.
5: Hacer clic en el botón azul "Crear token".
6: Desplazarse hacia abajo y seleccionar "Editar zona DNS -> Usar plantilla".
7: Agregar los siguientes permisos en el desplegable:

    ZONA -> CONFIGURACION DE ZONA -> LEER
    ZONA -> ZONA -> LEER
    ZONA -> DNS -> EDITAR
    
8: EN el desplegable "Recursos de zona" seleccionamos:

    INCLUIR -> TODAS LAS ZONAS
    
9: Ir a resumen y crear token.

10: En el input te aparecera el token, copialo y pegalo en un lugar seguro.


Ejecuta el siguiente script en la shell de tu nodo Proxmox.

bash <(curl -s https://raw.githubusercontent.com/esweb-es/proxmox-cloudflare-ddns/main/deploy-cloudflare-ddns.sh)
