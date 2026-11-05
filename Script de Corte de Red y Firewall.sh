#!/usr/bin/env bash
# ==============================================================================
# Nombre:       network_cutover.sh
# Descripción:  Automatiza la transición de red del servidor hacia Gigabit
#               Ethernet, abre los puertos del servicio DNS en UFW y deshabilita
#               la interfaz de radio Wi-Fi para optimizar latencia y temperatura.
# Uso:          sudo ./scripts/network_cutover.sh [OPCIONES]
# ==============================================================================

set -euo pipefail

# Valores por defecto parametrizables mediante variables de entorno o flags
ETH_INTERFACE="${ETH_INTERFACE:-}"
DNS_PORT="${DNS_PORT:-53}"
DISABLE_WIFI="${DISABLE_WIFI:-false}"

# Colores para salida estructurada
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}$*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}$*"; }
log_error() { echo -e "${RED}[ERROR]${NC}$*" >&2; }

show_help() {
    cat << EOF
Uso: sudo $(basename "$0") [OPCIONES]

Opciones:
  -i, --interface <IFACE>   Nombre de la interfaz Ethernet (ej: enp1s0f0).
                            Si se omite, el script intenta detectarla automáticamente.
  -p, --dns-port <PORT>     Puerto del servicio DNS a habilitar en UFW (Por defecto: 53).
  -w, --disable-wifi        Apaga la radio Wi-Fi una vez verificado el enlace Ethernet.
  -h, --help                Muestra este mensaje de ayuda y finaliza.

Ejemplo:
  sudo $(basename "$0") --interface enp1s0f0 --disable-wifi
EOF
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Este script requiere privilegios de superusuario. Ejecútelo con sudo."
        exit 1
    fi
}

detect_eth_interface() {
    if [[ -z "${ETH_INTERFACE}" ]]; then
        log_info "Detectando interfaz física Ethernet activa..."
        ETH_INTERFACE=$(ip -br link | awk '$1 ~ /^(en|eth)/ && $2 == "UP" {print $1; exit}')
        if [[ -z "${ETH_INTERFACE}" ]]; then
            log_error "No se detectó ninguna interfaz Ethernet en estado UP. Verifique el cable de red o especifique --interface."
            exit 1
        fi
        log_info "Interfaz detectada automáticamente: ${ETH_INTERFACE}"
    fi
}

verify_ethernet_ip() {
    local ip_addr
    ip_addr=$(ip -4 -br addr show "${ETH_INTERFACE}" 2>/dev/null | awk '{print $3}' || true)
    if [[ -z "${ip_addr}" ]]; then
        log_error "La interfaz '${ETH_INTERFACE}' no existe o no tiene dirección IPv4 asignada."
        exit 1
    fi
    log_info "Enlace verificado en ${ETH_INTERFACE} con dirección IPv4: ${ip_addr}"
}

configure_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        log_warn "UFW no está instalado en el sistema. Omitiendo configuración de firewall."
        return 0
    fi

    log_info "Configurando reglas de firewall UFW en ${ETH_INTERFACE} para el puerto${DNS_PORT} (TCP/UDP)..."
    ufw allow in on "${ETH_INTERFACE}" to any port "${DNS_PORT}" proto tcp
    ufw allow in on "${ETH_INTERFACE}" to any port "${DNS_PORT}" proto udp
    ufw reload
    log_info "Reglas de firewall aplicadas correctamente."
}

turn_off_wifi() {
    if [[ "${DISABLE_WIFI}" == "true" ]]; then
        if command -v nmcli >/dev/null 2>&1; then
            log_info "Apagando la radio Wi-Fi mediante NetworkManager..."
            nmcli radio wifi off
            log_info "Radio Wi-Fi deshabilitada exitosamente."
        else
            log_warn "nmcli no encontrado. No se pudo apagar la radio Wi-Fi automáticamente."
        fi
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--interface)
                ETH_INTERFACE="${2:-}"
                shift 2
                ;;
            -p|--dns-port)
                DNS_PORT="${2:-}"
                shift 2
                ;;
            -w|--disable-wifi)
                DISABLE_WIFI="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    check_root
    detect_eth_interface
    verify_ethernet_ip
    configure_ufw
    turn_off_wifi

    log_info "Resumen final de interfaces de red:"
    ip -br addr
    log_info "Corte de red completado con éxito."
}

main "$@"