# Capa 03: Observabilidad, Telemetría y Mantenimiento Autónomo

## 1. Contexto Técnico y Objetivos
Un servidor diseñado para operar de forma desatendida (*headless*) requiere dos pilares operativos:
1. **Observabilidad integral:** Monitorear en tiempo real las temperaturas de los núcleos del procesador, el estado térmico de las celdas de la batería, el consumo eléctrico y la disponibilidad de los servicios críticos.
2. **Automatización del ciclo de vida (CI/CD de Infraestructura):** Aplicar parches de seguridad del sistema operativo y actualizar las imágenes de los contenedores Docker durante ventanas de baja demanda (05:00 AM) sin intervención humana ni agotamiento del almacenamiento SSD.

---

## 2. Auditoría Térmica y de Recursos con Glances

A través del contenedor **Glances**, se monitorean los sensores físicos del kernel (`lm-sensors` / `applesmc`):

### Métricas de Referencia (Baseline Operativo)
* **Consumo de CPU en reposo/carga ligera:** ~14% a 20% (5.8 W de potencia de paquete).
* **Uso de Memoria RAM:** ~38% a 43%.
* **Temperaturas de CPU (`Core 0`, `Core 1`, `Package id 0`):** Entre **65°C y 72°C** (muy por debajo del umbral crítico `TjMax` de **105°C** de la arquitectura Intel Core móvil).
* **Sensores de Batería (`TB0T`, `TB1T`, `TB2T`):** Entre **26°C y 30°C**. Confirma aislamiento térmico total entre el disipador del procesador y las celdas de iones de litio, descartando riesgos de hinchazón o degradación química por calor.

---

## 3. Automatización de Actualizaciones del Sistema Operativo (Cron)

Para garantizar que el sistema operativo base, el kernel y los controladores reciban parches de seguridad diariamente a las **05:00 AM** sin bloquearse por cuadros de diálogo interactivos de `dpkg`:

### Configuración del Crontab de Superusuario
```bash
(sudo crontab -l 2>/dev/null; echo "0 5 * * * DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && apt-get autoremove -y >> /var/log/daily-update.log 2>&1") | sudo crontab -
```

### Anatomía del Comando
* `0 5 * * *`: Ejecución diaria a las 05:00 AM.
* `DEBIAN_FRONTEND=noninteractive`: Fuerza la resolución automática de consultas de configuración sin requerir entrada por teclado.
* `apt-get update && apt-get upgrade -y`: Sincroniza repositorios e instala actualizaciones aprobadas.
* `apt-get autoremove -y`: Purga dependencias huérfanas y kernels antiguos para liberar espacio en el SSD.
* `>> /var/log/daily-update.log 2>&1`: Redirige la salida estándar (`stdout`) y de errores (`stderr`) a un archivo de auditoría persistente.

**Criterio de Verificación (*Expected Output*):**
```bash
sudo crontab -l
```
Debe mostrar la tarea registrada. El historial de ejecución se audita mediante `cat /var/log/daily-update.log`.

---

## 4. Orquestación Autónoma de Contenedores con Watchtower

Dado que `apt-get` solo actualiza el sistema anfitrión, las aplicaciones contenerizadas (AdGuard Home, Uptime Kuma, Glances) se actualizan mediante **Watchtower** conectado al socket de Docker.

### Despliegue del Contenedor Watchtower
```bash
sudo docker run -d \
  --name watchtower \
  --restart always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e WATCHTOWER_SCHEDULE="0 0 5 * * *" \
  -e WATCHTOWER_CLEANUP=true \
  containrrr/watchtower
```

### Parámetros Clave
* `WATCHTOWER_SCHEDULE="0 0 5 * * *"`: Expresión cron de 6 campos (con segundos) que sincroniza la revisión de contenedores exactamente a las 05:00:00 AM.
* `WATCHTOWER_CLEANUP=true`: Elimina inmediatamente las imágenes Docker antiguas tras recrear un contenedor actualizado, evitando la saturación del disco SSD.

**Criterio de Verificación (*Expected Output*):**
```bash
sudo docker ps -f name=watchtower
sudo docker logs watchtower
```
La salida de `logs` debe reflejar la programación de la primera ejecución:
```text
Scheduling first run: YYYY-MM-DD 05:00:00
Note that the first check will be performed in X hours
```

---

## 5. Diagnóstico de Fallas Comunes (Troubleshooting)

| Síntoma / Error | Causa Raíz | Solución |
| :--- | :--- | :--- |
| Error de sintaxis al pegar el comando `docker run` multilínea. | Espacios en blanco o caracteres invisibles después de la barra invertida `\` en el emulador de terminal web. | Ejecutar el comando en una sola línea continua o mediante el script `scripts/setup_maintenance.sh`. |
| Watchtower se ejecuta en una hora distinta a las 05:00 AM locales. | El contenedor utiliza `UTC` por defecto si no hereda la zona horaria del host. | Añadir `-e TZ="America/Santiago"` (o la zona correspondiente) o montar `-v /etc/localtime:/etc/localtime:ro` al crear el contenedor. |
| `apt-get upgrade` falla por bloqueo de `/var/lib/dpkg/lock-frontend`. | Otro proceso de actualización estaba en curso en ese instante. | Verificar en `/var/log/daily-update.log` y ejecutar `sudo dpkg --configure -a` si un paquete quedó interrumpido. |