# Capa 00: Aprovisionamiento Bare-Metal, Endurecimiento Base y CasaOS

## 1. Contexto Técnico y Objetivos
Esta capa documenta el aprovisionamiento desde cero (*bare-metal*) de un nodo de cómputo x86_64 (laptop con chasis de aluminio y almacenamiento SSD), transformándolo en un servidor doméstico de alta disponibilidad sin interfaz gráfica permanente y capaz de operar de manera continua con la tapa cerrada (*clamshell mode*).

Objetivos específicos:
1. Desplegar un sistema operativo base estable y ligero (Linux Mint Cinnamon/XFCE o Debian/Ubuntu Server).
2. Inhibir por software la suspensión de energía por cierre de tapa a nivel del gestor de energía del kernel (`systemd-logind`).
3. Instalar de forma desatendida el motor de contenedores Docker, Docker Compose y la plataforma de orquestación CasaOS.
4. Establecer conectividad remota segura punto a punto mediante Tailscale.

---

## 2. Prerrequisitos y Dependencias
* **Hardware del Servidor:** Equipo x86_64 con almacenamiento SSD y tarjeta de red Ethernet/Wi-Fi.
* **Medio de Instalación:** Unidad USB (pendrive) de al menos 4 GB.
* **Herramientas del Administrador:** Software para flashear imágenes ISO (ej. BalenaEtcher o Rufus) e imagen ISO oficial de Linux Mint o Debian.

---

## 3. Procedimiento Paso a Paso

### Paso 1: Preparación del Medio de Instalación y BIOS/EFI
1. Descargar la imagen ISO oficial de Linux Mint.
2. Flashear la ISO en el pendrive USB mediante BalenaEtcher.
3. Conectar el pendrive al equipo destino y encenderlo manteniendo presionada la tecla de selección de arranque (`Option/Alt` en teclados Mac o `F12/F11` en PCs estándar).
4. Seleccionar la unidad externa EFI/USB e iniciar el instalador en modo Live.

---

### Paso 2: Instalación de Linux Mint en Almacenamiento SSD
1. En el escritorio Live, iniciar el asistente de instalación.
2. **Tipo de Instalación:** Seleccionar *Borrar disco e instalar Linux Mint* (o particionado manual asignando `/` en formato ext4 sobre el SSD).
3. **Identidad del Sistema:**
   * **Nombre de usuario:** Definir un usuario administrativo (ej. `<ADMIN_USER>`).
   * **Nombre del equipo (Hostname):** Asignar un identificador claro (ej. `homelab-node`).
   * **Inicio de sesión:** Marcar *Iniciar sesión automáticamente* para evitar bloqueos tras reinicios desatendidos.
4. Completar la instalación, retirar la unidad USB y reiniciar el equipo.

---

### Paso 3: Inhibición de Suspensión por Cierre de Tapa (Modo Clamshell)
Por defecto, Linux suspende el sistema al cerrar la tapa de una laptop. Para convertir el hardware en un servidor continuo con la pantalla apagada:

1. Modificar el archivo de configuración del gestor de energía de `systemd`:
   ```bash
   sudo sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
   sudo sed -i 's/#HandleLidSwitchExternalPower=suspend/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
   sudo sed -i 's/#HandleLidSwitchDocked=ignore/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
   ```
2. Reiniciar el servicio `systemd-logind` para aplicar los cambios sin reiniciar el host:
   ```bash
   sudo systemctl restart systemd-logind
   ```

**Criterio de Verificación (*Expected Output*):**
Al cerrar la tapa del equipo, la sesión SSH debe permanecer activa y los indicadores de red/alimentación deben mantenerse encendidos.

---

### Paso 4: Aprovisionamiento de Docker y Despliegue de CasaOS
1. Actualizar repositorios e instalar paquetes fundamentales:
   ```bash
   sudo apt-get update && sudo apt-get install -y curl wget git net-tools htop ufw
   ```
2. Ejecutar el instalador oficial desatendido de CasaOS (el cual audita el entorno e instala automáticamente el motor Docker y dependencias asociadas):
   ```bash
   curl -fsSL [https://get.casaos.io](https://get.casaos.io) | sudo bash
   ```

**Criterio de Verificación (*Expected Output*):**
El script finalizará mostrando el banner de éxito con las URLs de acceso local:
```text
   ____             ____   _____ 
  / ___|__ _ ___  / ___| / _ \ \
 | |   / _` / __| \___ \| | | | |
 | |__| (_| \__ \  ___) | |_| | |
  \____\__,_|___/ |____/ \___/_/ 

CasaOS v0.X.X is running on:
[http://192.168.1.](http://192.168.1.)X
```

---

### Paso 5: Despliegue de Red Mesh Zero-Trust (Tailscale)
Para habilitar la administración remota cifrada y segura sin exponer puertos en el router hacia internet:

1. Instalar Tailscale en el host:
   ```bash
   curl -fsSL [https://tailscale.com/install.sh](https://tailscale.com/install.sh) | sh
   ```
2. Iniciar el túnel e iniciar sesión:
   ```bash
   sudo tailscale up
   ```
3. Visitar el enlace de autenticación generado en el navegador del equipo de administración para autorizar el nodo en el panel de control de Tailscale.

**Criterio de Verificación (*Expected Output*):**
Ejecutar `tailscale ip -4` debe devolver una dirección IP fija asignada dentro del bloque CGNAT (`100.64.0.0/10`).

---

## 4. Diagnóstico de Fallas Comunes (Troubleshooting)

| Síntoma / Error | Causa Raíz | Solución |
| :--- | :--- | :--- |
| El servidor se apaga o pierde conectividad al cerrar la tapa. | La configuración de `logind.conf` no tomó los parámetros o existe un gestor de energía gráfico (XFCE Power Manager/GNOME Settings) sobreescribiendo el kernel. | Asegurar que `HandleLidSwitch=ignore` no tenga almohadilla (`#`) al inicio y ejecutar `sudo systemctl restart systemd-logind`. En entornos de escritorio, cambiar los ajustes en *Administración de Energía* a "No hacer nada al cerrar la tapa". |
| La instalación de CasaOS falla con error de conexión. | Ausencia de resolución DNS durante el instalador o puertos en conflicto. | Verificar `/etc/resolv.conf` y asegurarse de que el puerto `80` no esté tomado por otro servicio previo (`sudo lsof -i :80`). |
| Tailscale se desconecta periódicamente. | Modos de ahorro de energía en la tarjeta de red Wi-Fi/Ethernet. | Desactivar el ahorro de energía en la interfaz mediante `sudo iw dev <IFACE> set power_save off` o migrar a Ethernet cableado. |