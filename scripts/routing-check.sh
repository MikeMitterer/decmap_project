#!/usr/bin/env bash
#------------------------------------------------------------------------------
# routing-check.sh — Cross-Cutting-Drift-Guard (Domains / Routing-Praefixe)
#
# Prueft in EINEM Durchgang ueber den ganzen Baum (via find, umgeht gitignore ->
# auch apps/ + .env.example), dass Domains und Routing-Praefixe konsistent zur SoT
# sind. Zwei Ebenen:
#
#   1. Kanonische Hosts (proaktiv): Jeder <sub>.decisionmap.ai muss ein bekannter
#      Host sein — die kanonische Menge wird aus der SoT abgeleitet (nginx
#      server_name + Host-Teile der .env.example-Werte) + CANONICAL_EXTRA. Faengt
#      Tippfehler, stale Werte UND undeklarierte neue Subdomains, ohne den Alt-Wert
#      vorher zu kennen.
#   2. Veraltete Muster (reaktiv/Regression): explizite DEPRECATED-Liste fuer
#      Nicht-Host-Renames (z.B. Pfad /api/ -> /ai/).
#   3. Live .env (value-maskiert): die tatsaechlich aktiven .env (nicht .example,
#      nicht Backups) auf dieselben Hosts/Muster, aber Ausgabe NUR als "Key -> Host"
#      — nie die volle KEY=value-Zeile (haelt die .env-Leak-Regel).
#
# SoT: infrastructure/.env(.example) fuer Werte, nginx fuer die Routing-Struktur.
# Ergaenzt env-audit.py (.env <-> Code <-> compose) um nginx / Makefile / Scripts /
# Doku. Bewusste historische/Anti-Beispiel-Zeile: Marker `routing-check:ignore`;
# ganze Pfade via EXEMPT_RE.
#
# Verwendung:
#   ./scripts/routing-check.sh --check
#   make routing-check   |   make check
#
# Optionen:
#   -c | --check   Baum pruefen (Exit 1 bei Drift)
#   -v | --verbose wie --check, listet zusaetzlich alle geprueften Dateien
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

readonly PROJECT_DOMAIN='decisionmap.ai'
# Host-Muster: <sub.>*decisionmap.ai (auch bare decisionmap.ai).
readonly HOST_RE='([A-Za-z0-9_-]+\.)*decisionmap\.ai'

# Veraltete NICHT-Host-Muster (ERE) + Hinweis, "regex|hinweis". Host-Renames deckt
# der kanonische Check ab — hier nur Pfade/Praefixe u.ae. Bei einem Rename eintragen.
readonly DEPRECATED=(
    '/api/|ai-service laeuft jetzt unter /ai/ (nginx strippt den Praefix)'
)

# Kanonische Hosts, die NICHT aus nginx/.env ableitbar sind (Infra-only).
readonly CANONICAL_EXTRA=(
    'mail.decisionmap.ai'   # SES Custom MAIL FROM (DNS, nicht in .env/nginx)
    'cert.decisionmap.ai'   # systemd cert-watcher-Unit-Name (kein Service-Host)
)

# Hosts, die legitim in der Doku vorkommen, aber KEINE Service-Hosts sind — bewusste
# Anti-Beispiele / AWS-Vorschlaege. Werden nicht als Drift gewertet, aber auch nicht
# als kanonisch angezeigt (self-contained statt Marker in fremd-editierten Docs).
readonly DOC_ALLOWED=(
    'no-reply.decisionmap.ai'              # AWS-SES-Vorschlag, bewusst NICHT verwendet
    'mail.decisionmap.ai.decisionmap.ai'   # Hetzner-FQDN-Fehleingabe-Beispiel
)

# Ausgenommene Pfade: das Tool selbst, datierte/historische Docs, die SES/DNS-Doku
# (DNS-Records + Anti-Beispiele), Build-/VCS-/Tool-Verzeichnisse, lokale/gitignorierte
# .env (env-audits Domaene — .env.example bleibt gescannt) und Backups.
readonly EXEMPT_RE='routing-check\.sh|docs/plans/|docs/specs/|docs/security-audit-|docs/backend\.md|docs/ses-setup|design_handoff|design_claude_code_fail|/node_modules/|/\.venv/|/\.nuxt/|/\.output/|/\.git/|/\.pytest_cache/|/\.claude/|/\.superpowers/|/coverage/|/htmlcov/|/playwright-report/|/backups/|/dist/|/\.env$|/\.env\.bak|/\.env\.local|/\.env\.e2e\.local|\.backup$|\.orig$'

# Externe URLs, die zufaellig matchen (Nuxt-Doku-Links, Adminer-CSS, ...).
readonly EXTERNAL_RE='nuxt\.com|/docs/api/|github\.com|adminer|apache\.org'

# Binaer-/generierte Dateien (nach Name) — nie prueferelevant. Der Scan ist sonst
# typ-agnostisch (alle Text-Dateien), damit neue Quell-Dateitypen automatisch
# abgedeckt sind; grep -I filtert Binaeres zusaetzlich am Inhalt.
readonly BINARY_RE='\.(png|jpe?g|gif|svg|ico|webp|woff2?|ttf|eot|otf|pdf|zip|gz|tgz|jar|class|pyc|pyo|so|o|a|dylib|dll|exe|bin|wasm|mp4|mov|webm|db|sqlite3?|lock)$|package-lock\.json$|[^/]*-lock\.ya?ml$|\.min\.(js|css)$'

# Zeilen mit diesem Marker gelten als bewusst historisch/gewollt.
readonly IGNORE_MARKER='routing-check:ignore'

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-c | --check  " "Baum auf Domain-/Routing-Drift pruefen (Exit 1 bei Drift)"
    usageLine "-v | --verbose" "wie --check, listet zusaetzlich alle geprueften Dateien"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Pruefen:            ${GREEN}${APPNAME} --check${NC}   ${YELLOW}(oder: make routing-check / make check)${NC}"
    echo -e "    Neuer Host?         erst in ${CYAN}nginx server_name + .env.example${NC} deklarieren (SoT)"
    echo -e "    Nicht-Host-Rename?  alten Wert in ${CYAN}DEPRECATED${NC} (im Script) eintragen"
    echo -e "    Anti-Beispiel:      Zeile mit ${CYAN}${IGNORE_MARKER}${NC} markieren"
    echo
}

# Listet alle zu pruefenden Text-Dateien — typ-agnostisch via find (umgeht gitignore),
# EXEMPT_RE-Pfade + BINARY_RE-Dateien herausgefiltert. Bewusst KEINE Extension-Allowlist:
# ein neuer Quell-Dateityp (z.B. .sql/.tsx/.toml) ist damit automatisch abgedeckt.
#
# Returns:
#   Newline-separierte Dateipfade auf stdout
collectFiles() {
    find "${ROOT}" -type f 2>/dev/null \
        | grep -vE "${EXEMPT_RE}" \
        | grep -vE "${BINARY_RE}"
}

# Listet die LIVE .env-Dateien (.env / .env.local / .env.e2e.local) — bewusst NICHT
# .env.example (im Baum-Scan) und NICHT die .env.bak-*-Backups. Diese werden nur
# value-maskiert geprueft (checkEnvValues), nie mit vollen Zeilen ausgegeben.
#
# Returns:
#   Newline-separierte Dateipfade auf stdout
collectEnvFiles() {
    find "${ROOT}" -type f \
        \( -name '.env' -o -name '.env.local' -o -name '.env.e2e.local' \) 2>/dev/null \
        | grep -vE '/\.git/|/node_modules/|/backups/'
}

# Leitet die kanonische Menge der <sub>.decisionmap.ai-Hosts aus der SoT ab:
# nginx server_name-Direktiven + Host-Teile der .env.example-Werte + CANONICAL_EXTRA.
#
# Returns:
#   Sortierte, eindeutige Hostnamen (einer pro Zeile) auf stdout
canonicalHosts() {
    {
        grep -rhoE 'server_name[[:space:]]+[^;]+' \
            "${ROOT}/infrastructure/host/etc/nginx/"*.conf 2>/dev/null
        find "${ROOT}" -maxdepth 3 -name '.env.example' -not -path '*/.git/*' \
            -exec cat {} + 2>/dev/null
        printf '%s\n' "${CANONICAL_EXTRA[@]}"
    } | grep -oE "${HOST_RE}" | sort -u
}

# Gibt eine Fund-Zeile (Datei:Zeile-Treffer) eingerueckt und grau aus.
#
# Params:
#   $1 - Newline-Liste von "pfad:zeile:inhalt"
printHits() {
    printf '%s\n' "$1" | sed "s|${ROOT}/||" | while IFS= read -r hit_line; do
        echo -e "        ${GREY}${hit_line}${NC}"
    done
}

# Ebene 1 — prueft, dass jeder <sub>.decisionmap.ai im Baum kanonisch ist.
# Unbekannte Hosts (Tippfehler / stale / undeklarierte neue Subdomain) -> Fund.
#
# Params:
#   $1 - Newline-Liste der zu pruefenden Dateien
#
# Returns:
#   0 wenn alle Hosts kanonisch, 1 sonst
checkCanonicalHosts() {
    local files="$1" allowed found_hosts host esc locations found=0
    # Erlaubt = kanonisch (nginx+.env+EXTRA) + dokumentierte Nicht-Service-Hosts.
    allowed="$(canonicalHosts; printf '%s\n' "${DOC_ALLOWED[@]}")"
    found_hosts="$(printf '%s\n' "${files}" | xargs grep -IhoE "${HOST_RE}" 2>/dev/null | sort -u)"

    while IFS= read -r host; do
        if [[ -z "${host}" ]]; then continue; fi
        if grep -qxF "${host}" <<< "${allowed}"; then continue; fi
        esc="${host//./\\.}"
        locations="$(printf '%s\n' "${files}" | xargs grep -InE "${esc}" 2>/dev/null \
                     | grep -vE "${EXTERNAL_RE}" | grep -v "${IGNORE_MARKER}" || true)"
        if [[ -z "${locations}" ]]; then continue; fi
        found=1
        echo -e "    ${RED}✗ unbekannter Host:${NC} ${YELLOW}${host}${NC}  ${GREY}(nicht in nginx+.env — Tippfehler / stale / neue Subdomain nicht deklariert?)${NC}"
        printHits "${locations}"
    done <<< "${found_hosts}"
    return "${found}"
}

# Ebene 2 — prueft die expliziten DEPRECATED-Muster (Nicht-Host-Renames).
#
# Params:
#   $1 - Newline-Liste der zu pruefenden Dateien
#
# Returns:
#   0 wenn kein veraltetes Muster, 1 sonst
checkDeprecated() {
    local files="$1" found=0 entry pat hint hits
    for entry in "${DEPRECATED[@]}"; do
        pat="${entry%%|*}"
        hint="${entry#*|}"
        hits="$(printf '%s\n' "${files}" | xargs grep -InE "${pat}" 2>/dev/null \
                | grep -vE "${EXTERNAL_RE}" | grep -v "${IGNORE_MARKER}" || true)"
        if [[ -n "${hits}" ]]; then
            found=1
            echo -e "    ${RED}✗ veraltet:${NC} ${YELLOW}${pat}${NC}  ${GREY}→ ${hint}${NC}"
            printHits "${hits}"
        fi
    done
    return "${found}"
}

# Ebene 3 — prueft die LIVE .env-Werte auf veraltete Hosts/Muster, aber VALUE-MASKIERT:
# gibt ausschliesslich "<Key> → <Host/Muster>" aus, nie die volle KEY=value-Zeile. Das
# haelt die .env-Leak-Regel — ein <sub>.decisionmap.ai-Host ist eine oeffentliche Domain,
# der Rest des Werts (Credentials, Ports, Pfade) wird nie gedruckt. Nur aktive Assignments
# (Kommentare raus); env-audit deckt die volle Wert-Konsistenz leak-frei ab.
#
# Params:
#   $1 - Newline-Liste der zu pruefenden .env-Dateien
#
# Returns:
#   0 wenn sauber, 1 bei Fund (vom Aufrufer als nicht-blockierende Warnung behandelt)
checkEnvValues() {
    local env_files="$1" allowed file rel line key val host entry dep_pat found=0
    allowed="$(canonicalHosts; printf '%s\n' "${DOC_ALLOWED[@]}")"

    while IFS= read -r file; do
        if [[ -z "${file}" ]]; then continue; fi
        rel="${file#"${ROOT}"/}"
        while IFS= read -r line; do
            if [[ "${line}" == *"${IGNORE_MARKER}"* ]]; then continue; fi
            key="${line%%=*}"
            val="${line#*=}"
            # unbekannte decisionmap.ai-Hosts im Wert (nur der Host wird gedruckt)
            while IFS= read -r host; do
                if [[ -z "${host}" ]]; then continue; fi
                if grep -qxF "${host}" <<< "${allowed}"; then continue; fi
                found=1
                echo -e "    ${YELLOW}⚠${NC} ${GREY}${rel}:${NC} ${YELLOW}${key}${NC} → ${YELLOW}${host}${NC}  ${GREY}(unbekannter Host im .env-Wert)${NC}"
            done < <(printf '%s' "${val}" | grep -oE "${HOST_RE}" | sort -u)
            # veraltete Nicht-Host-Muster im Wert
            for entry in "${DEPRECATED[@]}"; do
                dep_pat="${entry%%|*}"
                if printf '%s' "${val}" | grep -qE "${dep_pat}" \
                   && ! printf '%s' "${val}" | grep -qE "${EXTERNAL_RE}"; then
                    found=1
                    echo -e "    ${YELLOW}⚠${NC} ${GREY}${rel}:${NC} ${YELLOW}${key}${NC} → ${YELLOW}${dep_pat}${NC}  ${GREY}(veraltetes Muster im .env-Wert)${NC}"
                fi
            done
        done < <(grep -vE '^[[:space:]]*#' "${file}" | grep '=' || true)
    done <<< "${env_files}"
    return "${found}"
}

# Fuehrt beide Check-Ebenen aus, zeigt vorab den Umfang (kanonische Hosts, Muster,
# Datei-Anzahl; bei "verbose" jede Datei).
#
# Params:
#   $1 - "verbose" um zusaetzlich jede gepruefte Datei aufzulisten (optional)
#
# Returns:
#   0 wenn keine Drift, 1 wenn Fund
runCheck() {
    local verbose="${1:-}"

    echo
    echo -e "  ${CYAN}Routing-Check${NC}  Domains/Routing konsistent zur SoT (nginx + .env)"
    echo "  ------------------------------------------------------------"

    local files file_count found=0 entry canon_host dep_pat file_path
    local env_files env_count
    files="$(collectFiles)"
    file_count="$(printf '%s\n' "${files}" | grep -c . || true)"
    env_files="$(collectEnvFiles)"
    env_count="$(printf '%s\n' "${env_files}" | grep -c . || true)"

    echo -e "  ${YELLOW}Kanonische Hosts (aus nginx + .env):${NC}"
    while IFS= read -r canon_host; do
        echo -e "      ${GREY}${canon_host}${NC}"
    done < <(canonicalHosts)
    echo -e "  ${YELLOW}Veraltete Muster:${NC}"
    for entry in "${DEPRECATED[@]}"; do
        echo -e "      ${CYAN}${entry%%|*}${NC}  ${GREY}→ ${entry#*|}${NC}"
    done
    if [[ "${verbose}" == "verbose" ]]; then
        echo -e "  ${YELLOW}Geprüfte Dateien (${file_count}):${NC}"
        printf '%s\n' "${files}" | sed "s|${ROOT}/||" | while IFS= read -r file_path; do
            echo -e "      ${GREY}${file_path}${NC}"
        done
    else
        echo -e "  ${YELLOW}Geprüfte Dateien:${NC} ${file_count}  ${GREY}(--verbose listet sie)${NC}"
    fi
    echo -e "  ${YELLOW}Live .env (value-maskiert):${NC} ${env_count}  ${GREY}(nur Key → Host, nie Werte — env-audit deckt Wert-Konsistenz ab)${NC}"
    echo

    local env_warn=0
    checkCanonicalHosts "${files}"     || found=1
    checkDeprecated     "${files}"     || found=1
    # Live-.env ist gitignoriert/persoenlich — Fund ist eine WARNUNG (sichtbar, aber
    # blockiert den Commit nicht; env-audit ist das Enforcement-Tool fuer .env-Werte).
    checkEnvValues      "${env_files}" || env_warn=1

    echo
    if [[ "${found}" -eq 1 ]]; then
        echo -e "  ${RED}✗ Drift gefunden${NC} — Files angleichen, neue Subdomain in nginx+.env deklarieren,"
        echo -e "    oder bewusstes Anti-Beispiel mit ${CYAN}${IGNORE_MARKER}${NC} markieren."
        echo
        return 1
    fi
    if [[ "${env_warn}" -eq 1 ]]; then
        echo -e "  ${YELLOW}⚠ Baum sauber — aber veraltete Routing-Werte in der lokalen .env (siehe oben).${NC}"
        echo -e "    ${GREY}Die lokale .env ist deine — ${CYAN}env-audit --check${GREY} zeigt die Wert-Drift; blockiert den Commit nicht.${NC}"
        echo
        return 0
    fi
    echo -e "  ${GREEN}✓ alle Domains kanonisch, keine veralteten Routing-Werte${NC}"
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
