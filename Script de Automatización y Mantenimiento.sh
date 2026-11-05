#!/usr/bin/env bash
# ==============================================================================
# Nombre:       setup_maintenance.sh
# Descripción:  Configura de forma idempotente el mantenimiento diario del
#               sistema operativo vía Cron y despliega Watchtower en Docker para
#               actualizar contenedores automáticamente en la ventana nocturna.
# Uso:          sudo ./scripts/setup_maintenance.sh [OPCIONES]
# ==============================================================================

set -euo pipefail

# Variables parametrizables por defecto
MAINTENANCE_HOUR="${MAINTENANCE_HOUR:-5}"
LOG_FILE="${LOG_FILE:-/var/log/daily-update.log}"
WATCHTOWER_NAME="${WATCHTOWER_NAME:-watchtower}"
TIMEZONE="${TIMEZONE:-UTC}"

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
  -H, --hour <0-23>         Hora del día para ejecutar el mantenimiento (Por defecto: 5).
  -l, --log-file <PATH>     Ruta del archivo de registro para apt (Por defecto: /var/log/daily-update.log).
  -n, --name <NAME>         Nombre del contenedor Watchtower (Por defecto: watchtower).
  -t, --timezone <TZ>       Zona horaria para Watchtower (ej: America/Santiago, Por defecto: UTC).
  -h, --help                Muestra este mensaje de ayuda y finaliza.

Ejemplo:
  sudo $(basename "$0") --hour 5 --timezone America/Santiago
EOF
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root o mediante sudo."
        exit 1
    fi
}

validate_hour() {
    if ! [[ "${MAINTENANCE_HOUR}" =~ ^[0-9]+$ ]] || (( MAINTENANCE_HOUR < 0 || MAINTENANCE_HOUR > 23 )); then
        log_error "La hora especificada ('${MAINTENANCE_HOUR}') no es válida. Debe ser un entero entre 0 y 23."
        exit 1
    fi
}

setup_os_cron() {
    log_info "Configurando tarea diaria de actualización del sistema operativo a las ${MAINTENANCE_HOUR}:00..."
    local cron_cmd="0 ${MAINTENANCE_HOUR} * * * DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && apt-get autoremove -y >> ${LOG_FILE} 2>&1"

    # Eliminar entradas previas que apunten al mismo archivo de log para garantizar idempotencia
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -v "${LOG_FILE}" || true)

    {
        if [[ -n "${current_cron}" ]]; then
            echo "${current_cron}"
        fi
        echo "${cron_cmd}"
    } | crontab -

    log_info "Crontab de root actualizado correctamente."
}

deploy_watchtower() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker no está instalado o no se encuentra en el PATH."
        exit 1
    fi

    log_info "Configurando contenedor '${WATCHTOWER_NAME}' para ejecución a las ${MAINTENANCE_HOUR}:00:00..."

    if docker ps -a --format '{{.Names}}' | grep -Eq "^${WATCHTOWER_NAME}$"; then
        log_warn "El contenedor '${WATCHTOWER_NAME}' ya existe. Recreando con los parámetros actuales..."
        docker rm -f "${WATCHTOWER_NAME}" >/dev/null
    fi

    docker run -d \
        --name "${WATCHTOWER_NAME}" \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -e TZ="${TIMEZONE}" \
        -e WATCHTOWER_SCHEDULE="0 0 ${MAINTENANCE_HOUR} * * *" \
        -e WATCHTOWER_CLEANUP=true \
        containrrr/watchtower >/dev/null

    log_info "Contenedor '${WATCHTOWER_NAME}' desplegado y activo."
}

verify_setup() {
    log_info "Verificando programación en Crontab:"
    crontab -l | grep "${LOG_FILE}"

    log_info "Verificando estado del contenedor Watchtower:"
    docker ps -f "name=${WATCHTOWER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -H|--hour)
                MAINTENANCE_HOUR="${2:-}"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="${2:-}"
                shift 2
                ;;
            -n|--name)
                WATCHTOWER_NAME="${2:-}"
                shift 2
                ;;
            -t|--timezone)
                TIMEZONE="${2:-}"
                shift 2
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
    validate_hour
    setup_os_cron
    deploy_watchtower
    verify_setup
    log_info "Pipeline de mantenimiento autónomo configurado exitosamente."
}

main "$@"