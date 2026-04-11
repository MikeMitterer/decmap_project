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
	@grep -hE '^(##@|[a-zA-Z_-]+:.*?## )' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; \
	    /^##@/ { printf "\n  ${YELLOW}%s${RESET}\n", substr($$0, 4) }; \
	    /^[^#]/ { printf "    ${BLUE}%-22s ${GREEN}%s${RESET}\n", $$1, $$2 }'
	@echo
	@echo "  ${YELLOW}Sub-Repo Makefiles${RESET}"
	@echo "    ${BLUE}make -C apps/backend help${RESET}          ${GREEN}Directus-Image, DB-Schema, Dev-Umgebung${RESET}"
	@echo "    ${BLUE}make -C apps/frontend help${RESET}         ${GREEN}Nuxt.js App (dev, lint, test, build)${RESET}"
	@echo "    ${BLUE}make -C apps/ai-service help${RESET}       ${GREEN}FastAPI (dev, test, build)${RESET}"
	@echo "    ${BLUE}make -C infrastructure help${RESET}        ${GREEN}Server-Orchestrierung, Backup${RESET}"
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

##@ Setup

.PHONY: setup
setup: ## Lokale .libs/-Symlinks erstellen (DEV_LOCAL muss gesetzt sein)
	@test -n "$${DEV_LOCAL}" || (echo "${RED}Fehler: DEV_LOCAL ist nicht gesetzt.${RESET}" && exit 1)
	ln -sf $${DEV_LOCAL}/DevBash/Production/BashLib  .libs/BashLib
	ln -sf $${DEV_LOCAL}/DevBash/Production/BashTools .libs/BashTools
	ln -sf $${DEV_LOCAL}/DevMake/Production/MakeLib   .libs/MakeLib
	@echo "${GREEN}Setup abgeschlossen.${RESET}"

##@ Daten

.PHONY: fixtures-sync
fixtures-sync: ## Fixtures aus data/ generieren (frontend + ai-service)
	python3 scripts/gen-fixtures.py

##@ Cross-Repo

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
