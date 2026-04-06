SHELL := /bin/bash

.DEFAULT_GOAL := help

WORKSPACE    := $(realpath $(shell pwd))
PROJECT_NAME := $(notdir $(WORKSPACE))

BACKEND    := backend
FRONTEND := frontend

include ${DEV_MAKE}/colours.mk
include ${DEV_MAKE}/tools.mk

# ─── Hilfe ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Alle verfügbaren Befehle anzeigen
	@echo
	@echo "Please use \`make <${YELLOW}target${RESET}>' where <target> is one of"
	@echo
	@echo "Project: ${YELLOW}$(PROJECT_NAME)${RESET}  (Workspace-Root — delegiert an Sub-Repos)"
	@echo
	@grep -hE '^(##@|[a-zA-Z_-]+:.*?## )' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; \
	    /^##@/ { printf "\n  ${YELLOW}%s${RESET}\n", substr($$0, 4) }; \
	    /^[^#]/ { printf "    ${BLUE}%-18s ${GREEN}%s${RESET}\n", $$1, $$2 }'
	@echo
	@echo "  ${YELLOW}Sub-Repo Makefiles${RESET}"
	@echo "    ${BLUE}make -C $(BACKEND) help${RESET}    ${GREEN}Alle Backend-Befehle (Docker, DB, Backup)${RESET}"
	@echo "    ${BLUE}make -C $(FRONTEND) help${RESET}  ${GREEN}Alle Frontend-Befehle (dev, lint, test, build)${RESET}"
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

##@ Entwicklung

.PHONY: dev-up
dev-up: ## Dev-Umgebung starten → backend/
	$(MAKE) -C $(BACKEND) dev-up

.PHONY: dev-down
dev-down: ## Dev-Umgebung stoppen → backend/
	$(MAKE) -C $(BACKEND) dev-down

##@ Code-Qualität (alle Repos)

.PHONY: lint
lint: ## Alle Linter ausführen (frontend + backend)
	$(MAKE) -C $(FRONTEND) lint
	@echo "${GREEN}Frontend lint ok.${RESET}"

.PHONY: format
format: ## Alle Formatter ausführen (frontend + backend)
	$(MAKE) -C $(FRONTEND) format
	@echo "${GREEN}Frontend format ok.${RESET}"

##@ Testing (alle Repos)

.PHONY: test
test: ## Alle Tests ausführen (frontend + backend)
	$(MAKE) -C $(FRONTEND) test
	@echo "${GREEN}Frontend tests ok.${RESET}"
