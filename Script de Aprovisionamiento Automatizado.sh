#!/usr/bin/env bash
# ==============================================================================
# Nombre:       bootstrap_server.sh
# Descripción:  Automatiza la configuración inicial de un nodo Linux para
#               operar como Home Lab: deshabilita la suspensión por cierre de tapa,
#               actualiza paquetes base, despliega CasaOS (Docker) e instala Tailscale.
# Uso:          sudo ./scripts/bootstrap_server.sh [OPCIONES]
# ==============================================================================

set -euo pipefail

# Variables por defecto
INSTALL_TAILSCALE="true"
INSTALL_CASAOS="true"
DISABLE_LID_SLEEP="true"

# Colores para salida estructurada
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

show_help() {
    cat << EOF
Uso: sudo $(basename "$0") [OPCIONES]

Opciones:
  --skip-casaos          Omite la instalación de CasaOS y Docker.
  --skip-tailscale       Omite la instalación y configuración de Tailscale.
  --skip-lid-config      Omite la reconfiguración de suspensión de tapa en systemd.
  -h, --help             Muestra este mensaje de ayuda y finaliza.

Ejemplo:
  sudo $(basename "$0")
EOF
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Este script requiere privilegios de superusuario. Ejecútelo con sudo."
        exit 1
    fi
}

configure_lid_switch() {
    if [[ "${DISABLE_LID_SLEEP}" == "true" ]]; then
        log_info "Configurando systemd-logind para ignorar el cierre de tapa (Modo Clamshell)..."
        local conf_file="/etc/systemd/logind.conf"
        
        # Eliminar comentarios y fijar la directiva en 'ignore'
        sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "${conf_file}"
        sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "${conf_file}"
        sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "${conf_file}"
        
        systemctl restart systemd-logind || log_warn "No se pudo reiniciar systemd-logind dinámicamente; requerirá reinicio."
        log_info "Configuración de energía actualizada exitosamente."
    fi
}

install_base_packages() {
    log_info "Actualizando listas de repositorios e instalando paquetes base..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl wget git net-tools htop ufw ca-certificates gnupg lsb-release
    log_info "Paquetes base instalados correctamente."
}

install_casaos() {
    if [[ "${INSTALL_CASAOS}" == "true" ]]; then
        log_info "Iniciando instalación oficial de CasaOS..."
        if command -v casaos >/dev/null 2>&1; then
            log_warn "CasaOS ya se encuentra instalado en el sistema."
        else
            curl -fsSL https://get.casaos.io | bash
            log_info "CasaOS instalado exitosamente."
        fi
    fi
}

install_tailscale() {
    if [[ "${INSTALL_TAILSCALE}" == "true" ]]; then
        log_info "Iniciando instalación de Tailscale..."
        if command -v tailscale >/dev/null 2>&1; then
            log_warn "Tailscale ya se encuentra instalado en el sistema."
        else
            curl -fsSL https://tailscale.com/install.sh | sh
            log_info "Tailscale instalado. Para asociar este nodo a su Tailnet, ejecute: sudo tailscale up"
        fi
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-casaos)
                INSTALL_CASAOS="false"
                shift
                ;;
            --skip-tailscale)
                INSTALL_TAILSCALE="false"
                shift
                ;;
            --skip-lid-config)
                DISABLE_LID_SLEEP="false"
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
    configure_lid_switch
    install_base_packages
    install_casaos
    install_tailscale

    log_info "=========================================================="
    log_info "Aprovisionamiento base completado exitosamente."
    log_info "Acceda a CasaOS vía navegador en la IP local de este equipo."
    log_info "Ejecute 'sudo tailscale up' para activar el acceso remoto."
    log_info "=========================================================="
}

main "$@"