#!/usr/bin/env bash
# repo-status.sh — Git-Status aller Workspace-Repos

REPOS=(
    ".:DecisionMap (Root)"
    "apps/backend:apps/backend"
    "apps/frontend:apps/frontend"
    "apps/ai-service:apps/ai-service"
    "infrastructure:infrastructure"
)

echo
printf "    \033[33m%-28s  %-20s  %s\033[0m\n" "Repo" "Lokal" "Remote"
printf "    %-28s  %-20s  %s\n" "----------------------------" "--------------------" "--------------------"

for entry in "${REPOS[@]}"; do
    path=${entry%%:*}
    name=${entry##*:}

    if [[ ! -d "$path/.git" ]]; then
        printf "    \033[34m%-28s\033[0m  \033[33m%s\033[0m\n" "$name" "nicht ausgecheckt"
        continue
    fi

    dirty=$(git -C "$path" status --porcelain 2>/dev/null)
    if [[ -n "$dirty" ]]; then
        n=$(echo "$dirty" | wc -l | tr -d ' ')
        local_col="\033[31m✗ $n unkommitiert\033[0m"
    else
        local_col="\033[32m✓ clean\033[0m"
    fi

    ahead=$(git -C "$path" rev-list --count @{upstream}..HEAD 2>/dev/null)
    behind=$(git -C "$path" rev-list --count HEAD..@{upstream} 2>/dev/null)

    if [[ -z "$ahead" ]]; then
        remote_col="\033[33mkein Remote\033[0m"
    elif [[ "$ahead" == "0" && "$behind" == "0" ]]; then
        remote_col="\033[32m✓ aktuell\033[0m"
    else
        remote_col=""
        [[ "$ahead"  != "0" ]] && remote_col="\033[33m↑ $ahead ahead\033[0m"
        [[ "$behind" != "0" ]] && remote_col="$remote_col \033[31m↓ $behind behind\033[0m"
    fi

    printf "    \033[34m%-28s\033[0m  %b  %b\n" "$name" "$local_col" "$remote_col"
done

echo
