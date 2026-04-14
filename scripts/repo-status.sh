#!/usr/bin/env bash
# repo-status.sh — Git-Status aller Workspace-Repos als formatierte Tabelle

set -euo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/colors.lib.sh";  fi
if [[ "${__TOOLS_LIB__:=""}"   == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";   fi

readonly REPOS=(
    ".:DecisionMap (Root)"
    "apps/backend:apps/backend"
    "apps/frontend:apps/frontend"
    "apps/ai-service:apps/ai-service"
    "infrastructure:infrastructure"
)

APPNAME="$(basename "$0")"
readonly APPNAME
readonly COL_WIDTH_NAME=28
readonly COL_WIDTH_LOCAL=20

# Zeigt die Verwendungshinweise an.
#
# Aufbau: Usage-Zeile, Optionen mit usageLine(), Hints-Sektion.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-s | --show   " "Git-Status aller Workspace-Repos als Tabelle anzeigen"
    usageLine "-h | --help   " "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Status anzeigen:    ${GREEN}${APPNAME} --show${NC}"
    echo
}

# Gibt den lokalen Commit-Status eines Repos zurück.
#
# Params:
#   $1 - Pfad zum Repo
#
# Returns:
#   Formatierter Status-String (coloriert)
get_local_status() {
    local repo_path="$1"

    local dirty_files
    dirty_files=$(git -C "${repo_path}" status --porcelain 2>/dev/null)

    if [[ -n "${dirty_files}" ]]; then
        local file_count
        file_count=$(echo "${dirty_files}" | wc -l | tr -d ' ')
        echo -e "${RED}✗ ${file_count} unkommitiert${NC}"
    else
        echo -e "${GREEN}✓ clean${NC}"
    fi
}

# Gibt den Remote-Sync-Status eines Repos zurück.
#
# Params:
#   $1 - Pfad zum Repo
#
# Returns:
#   Formatierter Status-String (coloriert), leer wenn kein Remote
get_remote_status() {
    local repo_path="$1"

    local ahead behind
    ahead=$(git  -C "${repo_path}" rev-list --count @{upstream}..HEAD 2>/dev/null || true)
    behind=$(git -C "${repo_path}" rev-list --count HEAD..@{upstream} 2>/dev/null || true)

    if [[ -z "${ahead}" ]]; then
        echo -e "${YELLOW}kein Remote${NC}"
        return
    fi

    if [[ "${ahead}" == "0" && "${behind}" == "0" ]]; then
        echo -e "${GREEN}✓ aktuell${NC}"
        return
    fi

    local status_parts=()
    [[ "${ahead}"  != "0" ]] && status_parts+=("${YELLOW}↑ ${ahead} ahead${NC}")
    [[ "${behind}" != "0" ]] && status_parts+=("${RED}↓ ${behind} behind${NC}")
    echo -e "${status_parts[*]}"
}

# Gibt die Tabellen-Kopfzeile aus.
print_header() {
    local separator_name separator_local
    separator_name="$(repeat '-' "${COL_WIDTH_NAME}")"
    separator_local="$(repeat '-' "${COL_WIDTH_LOCAL}")"

    local fmt_header fmt_separator
    fmt_header="    ${YELLOW}%-*s  %-*s  %s${NC}\n"
    fmt_separator="    %-*s  %-*s  %s\n"

    echo ""
    # shellcheck disable=SC2059
    printf "${fmt_header}" \
        "${COL_WIDTH_NAME}" "Repo" "${COL_WIDTH_LOCAL}" "Lokal" "Remote"
    # shellcheck disable=SC2059
    printf "${fmt_separator}" \
        "${COL_WIDTH_NAME}" "${separator_name}" \
        "${COL_WIDTH_LOCAL}" "${separator_local}" \
        "${separator_local}"
}

# Entfernt ANSI-Escape-Codes aus einem String.
#
# Params:
#   $1 - String mit ANSI-Codes
#
# Returns:
#   Reiner Text ohne Escape-Sequenzen
strip_ansi() {
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Gibt eine einzelne Repo-Zeile aus.
#
# Params:
#   $1 - Anzeigename des Repos
#   $2 - Pfad zum Repo (relativ zum Workspace-Root)
print_repo_row() {
    local repo_name="$1"
    local repo_path="$2"

    if [[ ! -d "${repo_path}/.git" ]]; then
        printf "    ${BLUE}%-${COL_WIDTH_NAME}s${NC}  ${YELLOW}%s${NC}\n" \
            "${repo_name}" "nicht ausgecheckt"
        return
    fi

    local local_status remote_status
    local_status=$(get_local_status "${repo_path}")
    remote_status=$(get_remote_status "${repo_path}")

    # Sichtbare Länge ohne ANSI berechnen, Lücke manuell auffüllen
    # ${#var} zählt Zeichen (nicht Bytes) — korrekt für UTF-8 Symbole wie ✓/✗
    local visible_text pad_len padding
    visible_text=$(strip_ansi "${local_status}" | tr -d '\n')
    pad_len=$(( COL_WIDTH_LOCAL - ${#visible_text} ))
    padding="$(repeat ' ' "${pad_len}")"

    printf "    ${BLUE}%-${COL_WIDTH_NAME}s${NC}  %b%s  %b\n" \
        "${repo_name}" "${local_status}" "${padding}" "${remote_status}"
}

# Gibt die Status-Tabelle aller konfigurierten Repos aus.
print_repos_table() {
    print_header

    for entry in "${REPOS[@]}"; do
        local repo_path="${entry%%:*}"
        local repo_name="${entry##*:}"
        print_repo_row "${repo_name}" "${repo_path}"
    done

    echo ""
}

# Gibt offene GitHub Issues mit Label 'blocker' oder 'high-priority' aus.
#
# Benötigt: gh CLI, authentifiziert
print_issues() {
    if ! command -v gh &>/dev/null; then
        return
    fi

    local issues
    issues=$(gh issue list \
        --repo MikeMitterer/decmap_project \
        --state open --limit 50 \
        --json number,title,labels \
        --jq '[.[] | select(.labels | map(.name) | any(. == "blocker" or . == "high-priority"))] | .[]' \
        2>/dev/null) || return

    if [[ -z "${issues}" ]]; then
        return
    fi

    echo -e "  ${YELLOW}Offene Issues (blocker / high-priority)${NC}"
    echo ""

    while IFS= read -r issue; do
        local number title labels_str label_color
        number=$(echo "${issue}" | jq -r '.number')
        title=$(echo "${issue}"  | jq -r '.title')
        labels_str=$(echo "${issue}" | jq -r '[.labels[].name] | join(", ")')

        if echo "${labels_str}" | grep -q "blocker"; then
            label_color="${RED}"
        else
            label_color="${YELLOW}"
        fi

        printf "    ${BLUE}#%-4s${NC}  %b%-12s${NC}  %s\n" \
            "${number}" "${label_color}" "[${labels_str}]" "${title}"
    done < <(echo "${issues}" | jq -c '.')

    echo ""
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

# Kein Argument → Help anzeigen
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -s|--show) print_repos_table; print_issues ;;
    -h|--help) usage; exit 0 ;;
    *)
        echo -e "${RED}Unbekannte Option: $1${NC}" >&2
        usage
        exit 1
        ;;
esac
