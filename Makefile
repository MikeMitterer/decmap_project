SHELL := /bin/bash

.DEFAULT_GOAL := help

WORKSPACE    := $(realpath $(shell pwd))
PROJECT_NAME := $(notdir $(WORKSPACE))

include ${DEV_MAKE}/colours.mk
include ${DEV_MAKE}/tools.mk

# ─── Hilfe ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Alle verfügbaren Befehle anzeigen
	@echo
	@echo "Please use \`make <${YELLOW}target${RESET}>' where <target> is one of"
	@echo
	@echo "Project: ${YELLOW}$(PROJECT_NAME)${RESET}  (Workspace-Root)"
	@echo
	@grep -hE '^(##@|[a-zA-Z0-9_-]+:.*?## )' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; \
	    /^##@/ { printf "\n  ${YELLOW}%s${RESET}\n", substr($$0, 4) }; \
	    /^[^#]/ { printf "    ${BLUE}%-22s ${GREEN}%s${RESET}\n", $$1, $$2 }'
	@echo

# ─── Info ────────────────────────────────────────────────────────────────────

.PHONY: info
info: ## Workspace-Umgebungsvariablen anzeigen
	@echo
	@echo "    ${YELLOW}PROJECT_NAME${RESET} = ${BLUE}$(PROJECT_NAME)${RESET}"
	@echo "    ${YELLOW}WORKSPACE${RESET}    = ${BLUE}$(WORKSPACE)${RESET}"
	@echo "    ${YELLOW}DEV_LOCAL${RESET}    = ${BLUE}$${DEV_LOCAL}${RESET}"
	@echo "    ${YELLOW}DEV_MAKE${RESET}     = ${BLUE}$${DEV_MAKE}${RESET}"
	@echo "    ${YELLOW}BASH_LIBS${RESET}    = ${BLUE}$${BASH_LIBS}${RESET}"
	@echo


.PHONY: hints
hints: ## Nützliche Links und Hinweise anzeigen
	@echo
	@echo "  ${YELLOW}GitHub Repositories${RESET}"
	@echo
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Root"           "https://github.com/MikeMitterer/decmap_project"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Backend"        "https://github.com/MikeMitterer/decmap_backend"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Frontend"       "https://github.com/MikeMitterer/decmap_frontend"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "AI-Service"     "https://github.com/MikeMitterer/decmap_ai-service"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Infrastructure" "https://github.com/MikeMitterer/decmap_infrastructure"
	@echo
	@echo "  ${YELLOW}Docker Images (ghcr.io/mangolila)${RESET}"
	@echo
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Directus"   "https://github.com/users/mangolila/packages/container/package/decisionmap-backend"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "Frontend"   "https://github.com/users/mangolila/packages/container/package/decisionmap-frontend"
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "AI-Service" "https://github.com/users/mangolila/packages/container/package/decisionmap-ai-service"
	@echo
	@echo "  ${YELLOW}Produktion${RESET}"
	@echo
	@printf "    ${BLUE}%-18s${RESET} ${WHITE}%s${RESET}\n" "App" "https://decisionmap.ai"
	@echo

##@ Setup

.PHONY: setup
setup: ## Lokale .libs/-Symlinks erstellen (DEV_LOCAL muss gesetzt sein)
	@test -n "$${DEV_LOCAL}" || (echo "${RED}Fehler: DEV_LOCAL ist nicht gesetzt.${RESET}" && exit 1)
	ln -sf $${DEV_LOCAL}/DevBash/Production/BashLib  .libs/BashLib
	ln -sf $${DEV_LOCAL}/DevBash/Production/BashTools .libs/BashTools
	ln -sf $${DEV_LOCAL}/DevMake/Production/MakeLib   .libs/MakeLib
	@echo "${GREEN}Setup abgeschlossen.${RESET}"


##@ Lokale Entwicklung

.PHONY: dev-up
dev-up: ## Alle Services starten (Docker im Hintergrund + overmind fuer Frontend + AI-Service)
	$(MAKE) -C apps/backend dev-up
	overmind start -f Procfile.dev

.PHONY: dev-down
dev-down: ## Docker-Services stoppen
	$(MAKE) -C apps/backend dev-down

##@ Workspace

.PHONY: status
status: ## Git-Status aller Repos (dirty + ahead/behind Remote)
	@bash scripts/repo-status.sh --show

.PHONY: loc
loc: ## Lines of Code zählen (tokei, alle Sub-Repos + Root)
	@tokei --hidden . apps/backend apps/frontend apps/ai-service infrastructure

##@ Daten

.PHONY: fakedata-sync
fakedata-sync: ## Fake-Daten aus data/ generieren (frontend + ai-service)
	python3 scripts/gen-fakedata.py --generate

##@ Versionierung

.PHONY: tags
tags: ## Letzte 10 Git-Tags anzeigen
	@echo
	@echo "  ${YELLOW}Letzte Tags — $(PROJECT_NAME)${RESET}"
	@echo
	@git tag --sort=-creatordate | head -10 | while read tag; do \
		printf "    ${BLUE}%-30s${RESET} ${WHITE}%s${RESET}\n" "$$tag" "$$(git log -1 --format='%ci' $$tag | cut -d' ' -f1)"; \
	done
	@echo


##@ Versionierung x-Repo

.PHONY: version
version: ## Aktuelle Versionen aller Sub-Repos anzeigen
	@echo
	@echo "  ${YELLOW}Versionen${RESET}"
	@echo
	@if [ -f apps/backend/VERSION ]; then \
		printf "    ${BLUE}%-20s${RESET} ${GREEN}%s${RESET}\n" "backend" "$$(cat apps/backend/VERSION)"; \
	else \
		printf "    ${BLUE}%-20s${RESET} ${WHITE}%s${RESET}\n" "backend" "(nicht ausgecheckt)"; \
	fi
	@if [ -f apps/frontend/package.json ]; then \
		printf "    ${BLUE}%-20s${RESET} ${GREEN}%s${RESET}\n" "frontend" "$$(grep '"version"' apps/frontend/package.json | head -1 | sed 's/.*"version": *"\(.*\)".*/\1/')"; \
	else \
		printf "    ${BLUE}%-20s${RESET} ${WHITE}%s${RESET}\n" "frontend" "(nicht ausgecheckt)"; \
	fi
	@if [ -f apps/ai-service/pyproject.toml ]; then \
		printf "    ${BLUE}%-20s${RESET} ${GREEN}%s${RESET}\n" "ai-service" "$$(grep '^version' apps/ai-service/pyproject.toml | head -1 | sed 's/version *= *"\(.*\)"/\1/')"; \
	else \
		printf "    ${BLUE}%-20s${RESET} ${WHITE}%s${RESET}\n" "ai-service" "(nicht ausgecheckt)"; \
	fi
	@echo

.PHONY: git-push-all
git-push-all: ## Git-Push in allen Repos (Root + Sub-Repos)
	@bash scripts/git-push-all.sh --show

##@ Docker x-Repo

.PHONY: build-all
build-all: ## Alle Docker-Images bauen (backend + frontend + ai-service)
	$(MAKE) -C apps/backend build
	$(MAKE) -C apps/frontend build
	$(MAKE) -C apps/ai-service build

.PHONY: push-all
push-all: ## Alle Images nach ghcr.io pushen
	$(MAKE) -C apps/backend push
	$(MAKE) -C apps/frontend push
	$(MAKE) -C apps/ai-service push

.PHONY: test-all
test-all: ## Alle Tests ausführen (backend + frontend + ai-service)
	$(MAKE) -C apps/backend test
	$(MAKE) -C apps/frontend test
	$(MAKE) -C apps/ai-service test

.PHONY: deploy
deploy: ## Full-Stack Deploy → infrastructure/
	$(MAKE) -C infrastructure deploy
