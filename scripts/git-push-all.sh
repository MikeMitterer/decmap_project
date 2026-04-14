#!/usr/bin/env bash
# git-push-all.sh — Git-Push in allen Workspace-Repos

set -euo pipefail

BASH_LIBS="${BASH_LIBS:-$(cd "$(dirname "$0")/../.libs/BashLib/src" && pwd)}"

if [[ "${__COLORS_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/colors.lib.sh"; fi

readonly REPOS=(
    ".:DecisionMap (Root)"
    "apps/backend:apps/backend"
    "apps/frontend:apps/frontend"
    "apps/ai-service:apps/ai-service"
    "infrastructure:infrastructure"
)

echo
echo -e "  ${YELLOW}Git Push — alle Repos${NC}"
echo

for entry in "${REPOS[@]}"; do
    repo_path="${entry%%:*}"
    repo_name="${entry##*:}"

    if [[ ! -d "${repo_path}/.git" ]]; then
        printf "    ${BLUE}%-22s${NC}  ${WHITE}(nicht ausgecheckt)${NC}\n" "${repo_name}"
        continue
    fi

    printf "    ${BLUE}%-22s${NC}  " "${repo_name}"
    if output=$(git -C "${repo_path}" push 2>&1); then
        echo -e "${GREEN}✓ ok${NC}"
    else
        echo -e "${RED}✗ Fehler${NC}"
        echo "${output}" | sed 's/^/        /'
    fi
done

echo
