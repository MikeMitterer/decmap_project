#!/usr/bin/env bash
# ─── DB Backup & Restore ───────────────────────────────────────────────────
# PostgreSQL-Backup/Restore via docker compose (custom format, komprimiert).
# Einheitliches Script für Backend (Dev) und Infrastructure (Prod).
#
# Verwendung:
#   db-backup.sh [OPTIONEN] backup
#   db-backup.sh [OPTIONEN] backup-schema
#   db-backup.sh [OPTIONEN] restore <file>
#   db-backup.sh [OPTIONEN] list
#   db-backup.sh --help
#
# Optionen / Env-Variablen:
#   --compose-file FILE   COMPOSE_FILE      Docker Compose File (optional, Standard: keines)
#   --service NAME        POSTGRES_SERVICE  Service-Name in Compose (Standard: postgres)
#   --backup-dir DIR      BACKUP_DIR        Backup-Verzeichnis    (Standard: ./backups)
#   --user USER           POSTGRES_USER     DB-Benutzer           (Standard: decisionmap)
#   --db NAME             POSTGRES_DB       Datenbank-Name        (Standard: decisionmap)
# ────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Defaults ───────────────────────────────────────────────────────────────

COMPOSE_FILE="${COMPOSE_FILE:-}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
POSTGRES_USER="${POSTGRES_USER:-decisionmap}"
POSTGRES_DB="${POSTGRES_DB:-decisionmap}"

# ─── Farben ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

die()  { echo -e "${RED}✗ $1${RESET}" >&2; exit 1; }
info() { echo -e "${BLUE}→ $1${RESET}"; }
ok()   { echo -e "${GREEN}✓ $1${RESET}"; }

# ─── Hilfe ──────────────────────────────────────────────────────────────────

usage() {
    echo "Verwendung: $(basename "$0") [OPTIONEN] {backup|backup-schema|restore <file>|list}"
    echo ""
    echo "Optionen:"
    echo "  --compose-file FILE   Docker Compose File  (oder COMPOSE_FILE)"
    echo "  --service NAME        Compose-Service-Name (Standard: postgres)"
    echo "  --backup-dir DIR      Backup-Verzeichnis   (Standard: ./backups)"
    echo "  --user USER           DB-Benutzer          (Standard: decisionmap)"
    echo "  --db NAME             Datenbank-Name       (Standard: decisionmap)"
    echo "  --help                Diese Hilfe anzeigen"
    echo ""
    echo "Befehle:"
    echo "  backup          Vollständiges Backup (Schema + Daten, custom format)"
    echo "  backup-schema   Nur Schema sichern (ohne Daten)"
    echo "  restore <file>  Backup wiederherstellen (drop + recreate DB)"
    echo "  list            Vorhandene Backups anzeigen"
    echo ""
    echo "Beispiele:"
    echo "  $(basename "$0") --compose-file docker-compose.dev.yml --backup-dir database/backups backup"
    echo "  $(basename "$0") --backup-dir backups restore backups/decisionmap_20260412_120000.dump"
}

# ─── Docker-Compose-Wrapper ─────────────────────────────────────────────────

dc_exec() {
    if [[ -n "${COMPOSE_FILE}" ]]; then
        docker compose -f "${COMPOSE_FILE}" exec "$@"
    else
        docker compose exec "$@"
    fi
}

check_service() {
    if ! dc_exec -T "${POSTGRES_SERVICE}" true 2>/dev/null; then
        local hint=""
        [[ -n "${COMPOSE_FILE}" ]] && hint=" (${COMPOSE_FILE})"
        die "Service '${POSTGRES_SERVICE}'${hint} nicht erreichbar. Compose läuft?"
    fi
}

# ─── Backup ─────────────────────────────────────────────────────────────────

do_backup() {
    local schema_only="${1:-false}"
    check_service
    mkdir -p "${BACKUP_DIR}"

    local timestamp filename filepath label extra_flags=""
    timestamp="$(date +%Y%m%d_%H%M%S)"

    if [[ "${schema_only}" == "true" ]]; then
        filename="schema_${POSTGRES_DB}_${timestamp}.dump"
        label="Schema-Backup"
        extra_flags="--schema-only"
    else
        filename="${POSTGRES_DB}_${timestamp}.dump"
        label="Backup"
    fi
    filepath="${BACKUP_DIR}/${filename}"

    info "${label}: ${POSTGRES_DB} → ${filename}"

    # shellcheck disable=SC2086
    dc_exec -T "${POSTGRES_SERVICE}" \
        pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        --format=custom --compress=6 --no-owner --no-acl \
        ${extra_flags} \
        > "${filepath}"

    local size
    size="$(du -h "${filepath}" | cut -f1)"
    ok "${label} gespeichert: ${BACKUP_DIR}/${filename} (${size})"
}

# ─── Restore ────────────────────────────────────────────────────────────────

do_restore() {
    local dump_file="$1"

    # Kein Verzeichnis-Anteil → Default-Backup-Dir voranstellen
    if [[ "${dump_file}" != */* ]]; then
        dump_file="${BACKUP_DIR}/${dump_file}"
    fi
    # Keine Extension → .dump anhängen
    if [[ "${dump_file}" != *.* ]]; then
        dump_file="${dump_file}.dump"
    fi
    # Relativen Pfad auflösen
    [[ "${dump_file}" = /* ]] || dump_file="${PWD}/${dump_file}"

    [[ -f "${dump_file}" ]] || die "Datei nicht gefunden: ${dump_file}"

    check_service

    local filename
    filename="$(basename "${dump_file}")"

    echo ""
    echo -e "${YELLOW}⚠  ACHTUNG: Restore überschreibt die Datenbank '${POSTGRES_DB}'!${RESET}"
    echo -e "${YELLOW}   Datei: ${filename}${RESET}"
    echo ""

    if [[ -t 0 ]]; then
        read -r -p "Fortfahren? [y/N] " confirm
        [[ "${confirm}" =~ ^[yY]$ ]] || { echo "Abgebrochen."; exit 0; }
    fi

    info "Bestehende Verbindungen trennen ..."
    dc_exec -T "${POSTGRES_SERVICE}" \
        psql -U "${POSTGRES_USER}" -d postgres -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();" \
        > /dev/null 2>&1 || true

    info "Datenbank droppen + neu anlegen ..."
    dc_exec -T "${POSTGRES_SERVICE}" dropdb  -U "${POSTGRES_USER}" --if-exists "${POSTGRES_DB}"
    dc_exec -T "${POSTGRES_SERVICE}" createdb -U "${POSTGRES_USER}" "${POSTGRES_DB}"

    info "Restore: ${filename} → ${POSTGRES_DB}"
    dc_exec -T "${POSTGRES_SERVICE}" \
        pg_restore -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        --no-owner --no-acl --single-transaction \
        < "${dump_file}"

    ok "Restore abgeschlossen. Services neu starten empfohlen."
}

# ─── List ───────────────────────────────────────────────────────────────────

do_list() {
    local dumps
    dumps="$(ls -1 "${BACKUP_DIR}"/*.dump 2>/dev/null || true)"

    if [[ -z "${dumps}" ]]; then
        echo "Keine Backups vorhanden in ${BACKUP_DIR}/"
        exit 0
    fi

    echo ""
    echo -e "${YELLOW}Vorhandene Backups (${BACKUP_DIR}/):${RESET}"
    echo ""

    ls -lhS "${BACKUP_DIR}"/*.dump 2>/dev/null | \
        awk '{printf "    %-12s %s\n", $5, $NF}' | \
        sed "s|${BACKUP_DIR}/||g"

    echo ""
    local count
    count="$(echo "${dumps}" | wc -l | tr -d ' ')"
    echo -e "    ${BLUE}${count} Backup(s)${RESET}"
    echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────────

[[ $# -gt 0 ]] || { usage; exit 1; }

CMD=""
REST_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --compose-file) COMPOSE_FILE="$2";     shift 2 ;;
        --service)      POSTGRES_SERVICE="$2"; shift 2 ;;
        --backup-dir)   BACKUP_DIR="$2";       shift 2 ;;
        --user)         POSTGRES_USER="$2";    shift 2 ;;
        --db)           POSTGRES_DB="$2";      shift 2 ;;
        --help|-h)      usage; exit 0 ;;
        backup|backup-schema|restore|list)
            CMD="$1"
            shift
            REST_ARGS=("$@")
            break
            ;;
        *) die "Unbekannte Option: $1" ;;
    esac
done

case "${CMD}" in
    backup)        do_backup false ;;
    backup-schema) do_backup true ;;
    restore)
        [[ ${#REST_ARGS[@]} -gt 0 ]] || die "Verwendung: restore <dump-file>"
        do_restore "${REST_ARGS[0]}"
        ;;
    list)          do_list ;;
    *)             usage; exit 1 ;;
esac
