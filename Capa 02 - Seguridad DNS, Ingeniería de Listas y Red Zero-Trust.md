# Capa 02: Seguridad DNS, Ingeniería de Listas y Red Zero-Trust

## 1. Contexto Técnico y Objetivos
El objetivo de esta capa es interceptar y filtrar la totalidad de las consultas DNS generadas tanto dentro de la red local (LAN) como fuera de ella (dispositivos en itinerancia), bloqueando dominios de publicidad, rastreo (*tracking*), telemetría de Smart TVs y malware sin degradar el tiempo de resolución ni romper sitios web legítimos.

---

## 2. Ingeniería de Listas de Bloqueo en AdGuard Home

### 2.1. El Problema de la Sobre-Suscripción de Reglas
Habilitar simultáneamente todas las listas de bloqueo disponibles genera dos problemas operativos:
1. **Degradación de Memoria y Latencia:** Millones de reglas duplicadas incrementan el consumo de RAM del contenedor y añaden latencia en la búsqueda de hashes en cada petición DNS.
2. **Falsos Positivos (*Broken Web*):** Listas extremadamente agresivas bloquean dominios de autenticación (SSO), pasarelas bancarias, enlaces transaccionales y servicios de streaming.

### 2.2. Matriz de Selección de Listas (El "Punto Dulce" Operativo)

| Lista Evaluada | Nivel de Agresividad | Decisión | Justificación Técnica |
| :--- | :--- | :--- | :--- |
| **AdGuard DNS Filter** | Moderado (Base) | **Activa** | Reglas base oficiales mantenidas para anuncios generales. |
| **OISD Blocklist Small** | Bajo | Descartada | Versión recortada para routers con poca memoria RAM; omite rastreadores modernos. |
| **OISD Blocklist Big** | Medio-Alto (Curado) | **Activa** | Excelente curaduría contra anuncios en Smart TVs y trackers móviles con tasa casi nula de falsos positivos. |
| **HaGeZi's Pro Blocklist** | Alto (Balanceado) | **Activa** | Bloquea telemetría agresiva de sistemas operativos y fabricantes de televisores (LG, Samsung) sin afectar la navegación diaria. |
| **HaGeZi's Pro++ / Ultimate** | Extremo | Descartada | Rompe funciones legítimas (Google Shopping, portales bancarios y redirecciones de marketing). Requiere mantenimiento manual constante (*whitelisting*). |

---

## 3. Estrategia frente al Bloqueo CPE/ONT del Proveedor (ISP)

### 3.1. Diagnóstico del Bloqueo en Equipos GPON (Ej. Huawei OptiXstar)
En conexiones residenciales de fibra óptica, los operadores bloquean el acceso de superusuario (`root`) en la interfaz web (`192.168.1.1`) y restringen la modificación del servidor DNS entregado por DHCP mediante plantillas de aprovisionamiento remoto **TR-069**. Además, los niveles básicos de soporte técnico suelen confundir la solicitud de una *reserva DHCP interna / cambio de DNS LAN* con la contratación de una *IP Pública Estática WAN* (exclusiva de planes corporativos).

### 3.2. Arquitecturas de Mitigación
Para implementar el filtrado sin contratar enlaces corporativos:

1. **Arquitectura A: Red Mesh Zero-Trust con Tailscale (PCs y Móviles Personales)**
   * Se registra la IP de Tailscale del servidor (`100.64.0.10`) como **Global Nameserver** en la consola de administración de Tailscale con la opción *Override local DNS* habilitada.
   * **Resultado:** Todo el tráfico DNS viaja cifrado hacia el servidor tanto dentro de la red doméstica como en redes móviles 4G/5G o Wi-Fi públicas.
2. **Arquitectura B: Asignación Estática con Failover en Dispositivos Fijos (Smart TVs / Familiares)**
   * En los ajustes de red Wi-Fi de los clientes locales, se define el direccionamiento DNS de forma manual:
     * **DNS Primario:** `192.168.1.10` (IP Ethernet del servidor AdGuard Home).
     * **DNS Secundario (Failover):** `1.1.1.1` (Cloudflare DNS).
   * **Justificación del Secundario (`1.1.1.1`):** Actúa como mecanismo de alta disponibilidad. Si el servidor entra en ventana de mantenimiento o se reinicia, los clientes conmutan automáticamente a Cloudflare evitando la caída del acceso a internet en el hogar.
3. **Arquitectura C: Router Neutro Propio en Cascada (Opcional)**
   * Conexión de un router neutro propio al puerto LAN de la ONT del proveedor, apagando el Wi-Fi del ISP y delegando la gestión DHCP/DNS íntegra al equipo propio.

---

## 4. Procedimiento de Configuración y Verificación

### Paso 1: Activación de Listas en AdGuard Home
1. Acceder al panel web en `http://<SERVER_LAN_IP>:8085` (o vía Tailscale en `http://<TAILSCALE_IP>:8085`).
2. Navegar a **Filtros** -> **Listas de bloqueo DNS** -> **Agregar lista de bloqueo** -> **Elegir de la lista**.
3. Marcar únicamente:
   * `AdGuard DNS filter`
   * `OISD Blocklist Big`
   * `HaGeZi's Pro Blocklist`
4. Guardar y actualizar las listas.

### Paso 2: Configuración de DNS en Clientes Locales
Configurar en el adaptador de red del cliente (Android / Smart TV / Windows):
* **Servidor DNS Preferido:** `192.168.1.10`
* **Servidor DNS Alternativo:** `1.1.1.1`

**Criterio de Verificación (*Expected Output*):**
En el **Panel de Control** de AdGuard Home:
* El contador de **Consultas DNS** incrementa en tiempo real al navegar desde los dispositivos.
* El porcentaje de **Bloqueado por filtros** se sitúa entre el **25% y el 50%** del tráfico total (interceptando dominios como `beacons.gcp.gvt2.com` y telemetría móvil).
* En **Clientes más frecuentes**, se listan tanto las IPs del segmento Tailscale (`100.x.y.z`) como las del segmento LAN (`192.168.1.x`).