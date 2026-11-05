# Capa 01: Infraestructura, Disipación Térmica y Corte de Red

## 1. Contexto Técnico y Objetivos
El reaprovechamiento de hardware portátil (arquitectura x86_64 con chasis de aluminio Unibody y almacenamiento sólido SSD) para operar como servidor 24/7 con la pantalla cerrada (*clamshell mode*) presenta desafíos térmicos y de conectividad:
1. **Gestión Térmica y Energética:** Disipar el calor generado por el procesador sin degradar ni inflar las celdas de la batería de polímero de litio.
2. **Estabilidad de Enlace de Red:** Eliminar la latencia variable (*jitter*) y la carga térmica del módulo inalámbrico Wi-Fi migrando el tráfico hacia una interfaz física Gigabit Ethernet.

---

## 2. Decisiones de Arquitectura Física

### 2.1. Batería Integrada como UPS en Línea vs. UPS Externa
En lugar de depender exclusivamente de un sistema de alimentación ininterrumpida (UPS) externo ubicado lejos del nodo de red, el servidor aprovecha su batería interna como un **UPS de conversión en línea (latencia de conmutación de 0 ms)**. Por ello, se prioriza situar el servidor a menos de 2 metros del router principal para garantizar una conexión física por cable Ethernet Cat 5e.

### 2.2. Disipación por Convección en Orientación Vertical
* **Viabilidad Mecánica:** Al utilizar almacenamiento 100% en estado sólido (SSD SATA III) sin partes móviles ni cabezales mecánicos, el equipo puede operar en posición vertical sin riesgo de fallo físico.
* **Ingeniería de Flujo de Aire:** En chasis Unibody, la expulsión del ventilador activo se ubica a lo largo de la bisagra trasera. Colocar el equipo en posición vertical apoyado sobre el canto lateral —dejando la bisagra apuntando hacia una zona libre y ambas caras de aluminio expuestas al aire— maximiza la transferencia térmica por convección natural y reduce la temperatura promedio entre **4°C y 8°C**.

### 2.3. Selección de Cableado Estructurado (Cat 5e vs. Cat 6)
Para enlaces cortos (menores a 5 metros) sobre tarjetas de red 1000BASE-T (1 Gbps) y planes de fibra óptica de hasta 800 Mbps, el estándar **Cat 5e** (100 MHz, soporte nativo de 1 Gbps hasta 100 metros) ofrece el mismo rendimiento efectivo que Cat 6, cuya ventaja real radica en la reducción de diafonía (*crosstalk*) mediante cruceta plástica interna para enlaces de 10 Gbps.

---

## 3. Prerrequisitos y Dependencias
* Sistema operativo Linux basado en Debian/Ubuntu con `NetworkManager` (`nmcli`), `iproute2` (`ip`) y `ufw` instalados.
* Acceso administrativo mediante `sudo`.
* Cable de red RJ-45 Cat 5e o superior conectado entre un puerto LAN del router y el puerto Gigabit Ethernet del servidor.

---

## 4. Procedimiento Paso a Paso

### Paso 1: Identificación de Interfaces de Red Predecibles
En distribuciones Linux modernas con `systemd/udev`, las interfaces físicas no utilizan la nomenclatura heredada (`eth0`), sino nombres predecibles basados en la topología PCI (por ejemplo, `enp1s0f0`).

```bash
ip -br addr
```

**Criterio de Verificación (*Expected Output*):**
```text
lo               UNKNOWN        127.0.0.1/8 ::1/128
enp1s0f0         UP             192.168.1.10/24
wlp2s0           UP             192.168.1.14/24
tailscale0       UNKNOWN        100.64.0.10/32
```
*Señal de éxito:* La interfaz cableada (`enp1s0f0`) muestra estado `UP` y cuenta con una dirección IPv4 válida asignada en el segmento local.

---

### Paso 2: Desactivación de la Radio Wi-Fi
Una vez confirmado el enlace cableado, se apaga por software el transceptor inalámbrico (`wlp2s0`) para eliminar pérdidas de paquetes, interferencias de radiofrecuencia y generación de calor en la placa lógica.

```bash
sudo nmcli radio wifi off
```

**Criterio de Verificación (*Expected Output*):**
Al ejecutar nuevamente `ip -br addr`, la interfaz inalámbrica debe figurar como `DOWN`:
```text
enp1s0f0         UP             192.168.1.10/24
wlp2s0           DOWN
```

---

### Paso 3: Actualización de Reglas del Firewall (UFW) para la Interfaz Cableada
Para permitir que los clientes de la red local consulten el servicio DNS (puerto 53 TCP y UDP) a través de la nueva tarjeta física:

```bash
sudo ufw allow in on <ETH_INTERFACE> to any port 53 proto tcp
sudo ufw allow in on <ETH_INTERFACE> to any port 53 proto udp
sudo ufw reload
```
*(Reemplazar `<ETH_INTERFACE>` por el identificador obtenido en el Paso 1, ej. `enp1s0f0`).*

**Criterio de Verificación (*Expected Output*):**
```text
Rule added
Rule added
Firewall reloaded
```

---

## 5. Diagnóstico de Fallas Comunes (Troubleshooting)

| Síntoma / Error | Causa Raíz | Solución |
| :--- | :--- | :--- |
| `Device "eth0" does not exist.` | El kernel utiliza *Predictable Network Interface Names* en lugar de `eth0`. | Ejecutar `ip -br addr` o `nmcli device` para identificar el nombre real de la tarjeta PCI (`enp1s0f0`, `eno1`, etc.). |
| `Error: failed to set Wi-Fi radio: Not authorized to perform this operation` | `NetworkManager` requiere privilegios de superusuario (`polkit`) para alterar el estado físico del hardware de radio. | Anteponga `sudo` al comando: `sudo nmcli radio wifi off`. |
| Temperatura elevada en la carcasa (> 75°C en reposo). | Obstrucción de la rejilla de la bisagra trasera o contacto directo del chasis inferior con madera/superficie aislante. | Elevar el equipo 2 cm con topes o colocarlo en soporte vertical con la bisagra apuntando hacia arriba. |