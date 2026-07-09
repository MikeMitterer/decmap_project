#!/usr/bin/env bash
#------------------------------------------------------------------------------
# routing-check.sh — Cross-Cutting-Drift-Guard (Domains / Routing-Praefixe)
#
# Findet veraltete Domain-/Routing-Werte, die nach einem Rename in aktivem Code,
# Config, Scripts, Makefiles oder Doku zurueckgeblieben sind — in EINEM Durchgang
# ueber den ganzen Baum (via find, umgeht gitignore -> auch apps/ + .env.example),
# statt sie ueber viele Iterationen manuell zusammenzugreppen.
#
# SoT: infrastructure/.env(.example) fuer Werte, nginx fuer die Routing-Struktur
# (nginx server_name / Location-Pfade lassen sich nicht aus .env variablisieren).
# Ergaenzt env-audit.py (das .env <-> Code <-> compose deckt) um nginx / Makefile /
# Scripts / Doku.
#
# Bei einem Rename (ALT -> NEU): ALT in der DEPRECATED-Liste eintragen, dann
# `make routing-check` — meldet alle betroffenen Files. Bewusste historische Zeile:
# Marker `routing-check:ignore`; ganze Pfade via EXEMPT_RE.
#
# Verwendung:
#   ./scripts/routing-check.sh --check
#   make routing-check
#
# Optionen:
#   -c | --check   Baum auf veraltete Domain-/Routing-Werte pruefen (Exit 1 bei Drift)
#   -h | --help    Diese Hilfe anzeigen
#------------------------------------------------------------------------------
set -euo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/colors.lib.sh";  fi
if [[ "${__TOOLS_LIB__:=""}"   == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";   fi

APPNAME="$(basename "$0")"
readonly APPNAME
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly ROOT

# Veraltete Muster (ERE) + Hinweis im Format "regex|hinweis". Bei einem Rename den
# ALTEN Wert hier eintragen — dann findet ein Lauf alle verbliebenen Vorkommen.
readonly DEPRECATED=(
    '/api/|ai-service laeuft jetzt unter /ai/ (nginx strippt den Praefix)'
    'api\.decisionmap\.ai|Backend-Subdomain ist jetzt backend.decisionmap.ai'
)

# Ausgenommene Pfade: das Tool selbst (enthaelt die Muster als Config), datierte/
# historische Docs (Point-in-Time), Build-/VCS-Verzeichnisse.
readonly EXEMPT_RE='routing-check\.sh|docs/plans/|docs/specs/|docs/security-audit-|docs/backend\.md|design_handoff|design_claude_code_fail|/node_modules/|/\.venv/|/\.nuxt/|/\.output/|/\.git/|/\.pytest_cache/|/\.claude/|/backups/|/dist/'

# Externe URLs, die zufaellig matchen (Nuxt-Doku-Links, Adminer-CSS, ...).
readonly EXTERNAL_RE='nuxt\.com|/docs/api/|github\.com|adminer|apache\.org'

# Zeilen mit diesem Marker gelten als bewusst historisch/gewollt.
readonly IGNORE_MARKER='routing-check:ignore'

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-c | --check  " "Baum auf veraltete Domain-/Routing-Werte pruefen (Exit 1 bei Drift)"
    usageLine "-v | --verbose" "wie --check, listet zusaetzlich alle geprueften Dateien"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Pruefen:            ${GREEN}${APPNAME} --check${NC}   ${YELLOW}(oder: make routing-check)${NC}"
    echo -e "    Bei einem Rename:   alten Wert in ${CYAN}DEPRECATED${NC} (im Script) eintragen"
    echo -e "    Historische Zeile:  mit ${CYAN}${IGNORE_MARKER}${NC} markieren"
    echo
}

# Listet alle zu pruefenden Text-Dateien — via find (umgeht gitignore), Pfade aus
# EXEMPT_RE herausgefiltert.
#
# Returns:
#   Newline-separierte Dateipfade auf stdout
collectFiles() {
    find "${ROOT}" -type f \
        \( -name '*.ts' -o -name '*.vue' -o -name '*.js' -o -name '*.py' \
           -o -name '*.sh' -o -name '*.md' -o -name '*.yml' -o -name '*.yaml' \
           -o -name '*.conf' -o -name '*.example' -o -name 'Makefile' \
           -o -name 'Dockerfile' -o -name 'Jenkinsfile' -o -name 'Procfile*' \
           -o -name '*.json' \) 2>/dev/null | grep -vE "${EXEMPT_RE}"
}

# Prueft den Baum gegen alle DEPRECATED-Muster und gibt Treffer coloriert aus.
# Zeigt vorab den Umfang (Muster + Datei-Anzahl); bei "verbose" jede Datei.
#
# Params:
#   $1 - "verbose" um zusaetzlich jede gepruefte Datei aufzulisten (optional)
#
# Returns:
#   0 wenn keine Drift, 1 wenn veraltete Werte gefunden
runCheck() {
    local verbose="${1:-}"

    echo
    echo -e "  ${CYAN}Routing-Check${NC}  veraltete Domains/Routing im ganzen Baum"
    echo "  ------------------------------------------------------------"

    local files file_count found=0 entry pat hint hits hit_line
    files="$(collectFiles)"
    file_count="$(printf '%s\n' "${files}" | grep -c . || true)"

    echo -e "  ${YELLOW}Geprüfte Muster:${NC}"
    for entry in "${DEPRECATED[@]}"; do
        echo -e "      ${CYAN}${entry%%|*}${NC}  ${GREY}→ ${entry#*|}${NC}"
    done
    if [[ "${verbose}" == "verbose" ]]; then
        echo -e "  ${YELLOW}Geprüfte Dateien (${file_count}):${NC}"
        printf '%s\n' "${files}" | sed "s|${ROOT}/||" | while IFS= read -r hit_line; do
            echo -e "      ${GREY}${hit_line}${NC}"
        done
    else
        echo -e "  ${YELLOW}Geprüfte Dateien:${NC} ${file_count}  ${GREY}(--verbose listet sie)${NC}"
    fi
    echo

    for entry in "${DEPRECATED[@]}"; do
        pat="${entry%%|*}"
        hint="${entry#*|}"
        hits="$(printf '%s\n' "${files}" | xargs grep -nE "${pat}" 2>/dev/null \
                | grep -vE "${EXTERNAL_RE}" | grep -v "${IGNORE_MARKER}" || true)"
        if [[ -n "${hits}" ]]; then
            found=1
            echo -e "    ${RED}✗ veraltet:${NC} ${YELLOW}${pat}${NC}  ${CYAN}→ ${hint}${NC}"
            printf '%s\n' "${hits}" | sed "s|${ROOT}/||" | while IFS= read -r hit_line; do
                echo -e "        ${hit_line}"
            done
        fi
    done

    echo
    if [[ "${found}" -eq 1 ]]; then
        echo -e "  ${RED}✗ Drift gefunden${NC} — Files angleichen, oder historische Zeile mit ${CYAN}${IGNORE_MARKER}${NC} markieren."
        echo
        return 1
    fi
    echo -e "  ${GREEN}✓ keine veralteten Domain-/Routing-Werte in aktiven Files${NC}"
    echo
    return 0
}

# Kein Argument → Help anzeigen (kein stilles Loslegen).
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -c|--check)   runCheck ;;
    -v|--verbose) runCheck verbose ;;
    -h|--help)    usage; exit 0 ;;
    *) echo -e "${RED}Unbekannte Option: $1${NC}" >&2; usage; exit 1 ;;
esac
