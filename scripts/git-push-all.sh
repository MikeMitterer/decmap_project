#!/usr/bin/env bash
#------------------------------------------------------------------------------
# git-push-all.sh — Git-Push in allen Workspace-Repos
#
# Pusht Root-Repo (DecisionMap) und alle Sub-Repos in definierter Reihenfolge.
# Gibt pro Repo einen farbigen Status aus (✓ ok / ✗ Fehler).
# Nicht ausgecheckte Repos werden übersprungen.
#
# Verwendung:
#   ./scripts/git-push-all.sh [--push] [--help]
#   make git-push-all
#
# Optionen:
#   --push   Push in allen Repos ausführen
#------------------------------------------------------------------------------

set -euo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi
if [[ "${__TOOLS_LIB__:=""}"  == "" ]]; then . "${BASH_LIBS}/tools.lib.sh";  fi

APPNAME="$(basename "$0")"
readonly APPNAME

readonly REPOS=(
    ".:DecisionMap (Root)"
    "apps/backend:apps/backend"
    "apps/frontend:apps/frontend"
    "apps/ai-service:apps/ai-service"
    "infrastructure:infrastructure"
)

# Zeigt die Verwendungshinweise an.
usage() {
    echo
    echo "Usage: ${APPNAME} [ options ]"
    echo
    usageLine "-p | --push" "Git-Push in allen Workspace-Repos ausführen"
    usageLine "-h | --help" "Diese Hilfe anzeigen"
    echo
    echo -e "${LIGHT_BLUE}Hints:${NC}"
    echo -e "    Push ausführen:  ${GREEN}${APPNAME} --push${NC}"
    echo
}

# Pusht alle konfigurierten Repos und gibt Status pro Repo aus.
pushAll() {
    echo
    echo -e "  ${YELLOW}Git Push — alle Repos${NC}"
    echo

    for entry in "${REPOS[@]}"; do
        local repo_path="${entry%%:*}"
        local repo_name="${entry##*:}"

        if [[ ! -d "${repo_path}/.git" ]]; then
            printf "    ${BLUE}%-22s${NC}  ${YELLOW}(nicht ausgecheckt)${NC}\n" "${repo_name}"
            continue
        fi

        printf "    ${BLUE}%-22s${NC}  " "${repo_name}"
        if output=$(git -C "${repo_path}" push 2>&1); then
            echo -e "${GREEN}✓ ok${NC}"
        else
            echo -e "${RED}✗ Fehler${NC}"
            while IFS= read -r line; do echo "        ${line}"; done <<< "${output}"
        fi
    done

    echo
}

# ─── Entry Point ──────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    -p|--push) pushAll ;;
    -h|--help) usage; exit 0 ;;
    *) echo -e "${RED}Unbekannte Option: $1${NC}" >&2; usage; exit 1 ;;
esac
