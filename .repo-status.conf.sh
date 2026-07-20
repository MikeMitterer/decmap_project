#!/usr/bin/env bash
# Config fuer repo-status.sh (ProjectTools) — wird gesourced, kein Custom-Parser.
# .sh-Endung fuers IDE-Highlighting. Format-Doku: ProjectTools/README.md
# shellcheck disable=SC2034  # von repo-status.sh gesourct

# Optional: GitHub-Repo fuer die Issue-Sektion (blocker/high-priority)
ISSUES_REPO="MikeMitterer/decmap_project"

# Workspace-Repos: "<pfad>:<anzeigename>"
REPOS=(
    ".:DecisionMap (Root)"
    "apps/backend:apps/backend"
    "apps/frontend:apps/frontend"
    "apps/ai-service:apps/ai-service"
    "infrastructure:infrastructure"
)
