#!/usr/bin/env bash
#------------------------------------------------------------------------------
# routing-check.sh — Cross-Cutting-Drift-Guard (Domains / Routing-Praefixe)
#
# Findet veraltete Domain-/Routing-Werte, die nach einem Rename in aktivem Code,
# Config, Scripts, Makefiles oder Doku zurueckgeblieben sind — in EINEM Durchgang
# ueber den ganzen Baum (auch gitignorierte apps/ + .env.example), statt sie ueber
# viele Iterationen manuell zusammenzugreppen.
#
# SoT: infra/.env(.example) fuer Werte, nginx fuer die Routing-Struktur. Ueberall
# sonst per Variable ableiten; wo hardcoded unvermeidbar ist (nginx server_name /
# Location-Pfade), faengt dieses Tool die Drift.
#
# Ergaenzt env-audit.py: env-audit deckt .env <-> Code <-> compose ab,
# routing-check deckt nginx / Makefile / Scripts / Doku.
#
# Bei einem Rename (ALT -> NEU): ALT in der DEPRECATED-Liste eintragen,
# `make routing-check` laufen, alle gemeldeten Files angleichen. Der Eintrag bleibt
# als Regressions-Guard. Bewusste historische Erwaehnung: Zeile mit dem Marker
# `routing-check:ignore` versehen; ganze Pfade via EXEMPT_RE.
#
# Verwendung:
#   routing-check.sh            pruefen (Exit 1 bei Drift)
#   routing-check.sh --help
#------------------------------------------------------------------------------
set -euo pipefail

APPNAME="$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Veraltete Muster (ERE) + Hinweis, "regex|hinweis". Bei Rename ALT hier eintragen.
DEPRECATED=(
    '/api/|ai-service laeuft jetzt unter /ai/ (nginx strippt den Praefix)'
    'api\.decisionmap\.ai|Backend-Subdomain ist jetzt backend.decisionmap.ai'
)

# Ausgenommene Pfade: das Tool selbst (enthaelt die Muster als Config), datierte/
# historische Artefakte + Build-/VCS-Verzeichnisse.
EXEMPT_RE='routing-check\.sh|docs/plans/|docs/specs/|docs/security-audit-|docs/backend\.md|design_handoff|design_claude_code_fail|/node_modules/|/\.venv/|/\.nuxt/|/\.output/|/\.git/|/backups/|/dist/'

# Externe URLs, die zufaellig matchen (Nuxt-Doku-Links, Adminer-CSS, ...).
EXTERNAL_RE='nuxt\.com|/docs/api/|github\.com|adminer|apache\.org'

# Zeilen mit diesem Marker gelten als bewusst historisch/gewollt.
IGNORE_MARKER='routing-check:ignore'

if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'; GREY=$'\033[0;90m'; RESET=$'\033[0m'
else
    RED=; GREEN=; YELLOW=; CYAN=; GREY=; RESET=
fi

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "  ${CYAN}${APPNAME}${RESET} — Cross-Cutting-Drift-Guard (Domains / Routing)"
    echo
    echo "  Prueft den ganzen Baum auf veraltete Domain-/Routing-Werte nach einem"
    echo "  Rename. SoT: infra/.env + nginx. Ergaenzt env-audit (.env/Code/compose)."
    echo
    echo "  ${YELLOW}Verwendung:${RESET}"
    echo "    ${GREEN}${APPNAME}${RESET}            pruefen (Exit 1 bei Drift)"
    echo "    ${GREEN}${APPNAME} --help${RESET}     diese Hilfe"
    echo
    echo "  ${YELLOW}Bei einem Rename${RESET} (ALT -> NEU): ALT in DEPRECATED (im Script) eintragen,"
    echo "  dann ${GREEN}make routing-check${RESET} — findet alle betroffenen Files in einem Durchgang."
    echo "  Bewusste historische Zeile: mit ${CYAN}${IGNORE_MARKER}${RESET} markieren."
    echo
}

# Listet alle zu pruefenden Text-Dateien (bypass gitignore via find).
collect_files() {
    find "$ROOT" -type f \
        \( -name '*.ts' -o -name '*.vue' -o -name '*.js' -o -name '*.py' \
           -o -name '*.sh' -o -name '*.md' -o -name '*.yml' -o -name '*.yaml' \
           -o -name '*.conf' -o -name '*.example' -o -name 'Makefile' \
           -o -name 'Dockerfile' -o -name 'Jenkinsfile' -o -name 'Procfile*' \
           -o -name '*.json' \) 2>/dev/null | grep -vE "$EXEMPT_RE"
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
    esac

    echo
    echo "  ${CYAN}Routing-Check${RESET} ${GREY}(veraltete Domains/Routing im ganzen Baum)${RESET}"
    echo "  ------------------------------------------------------------"

    local files found=0 entry pat hint hits
    files="$(collect_files)"

    for entry in "${DEPRECATED[@]}"; do
        pat="${entry%%|*}"
        hint="${entry#*|}"
        hits="$(printf '%s\n' "$files" | xargs grep -nE "$pat" 2>/dev/null \
                | grep -vE "$EXTERNAL_RE" | grep -v "$IGNORE_MARKER" || true)"
        if [ -n "$hits" ]; then
            found=1
            echo "    ${RED}✗ veraltet:${RESET} ${YELLOW}${pat}${RESET}  ${GREY}→ ${hint}${RESET}"
            printf '%s\n' "$hits" | sed "s|${ROOT}/||" | while IFS= read -r l; do
                echo "        ${GREY}${l}${RESET}"
            done
        fi
    done

    echo
    if [ "$found" -eq 1 ]; then
        echo "  ${RED}✗ Drift gefunden${RESET} — Files angleichen, oder historische Zeile mit ${CYAN}${IGNORE_MARKER}${RESET} markieren."
        echo
        exit 1
    fi
    echo "  ${GREEN}✓ keine veralteten Domain-/Routing-Werte in aktiven Files${RESET}"
    echo
}

main "$@"
