SHELL := /bin/bash

.DEFAULT_GOAL := help

WORKSPACE    := $(realpath $(shell pwd))
PROJECT_NAME := $(notdir $(WORKSPACE))

include ${DEV_MAKE}/colours.mk
include ${DEV_MAKE}/tools.mk

-include .env
export

# ─── Precheck ────────────────────────────────────────────────────────────────

precheck:
	@if [[ -z "$${BASH_LIBS+x}" ]]; then \
		echo ""; \
		echo "${RED}Achtung: '${YELLOW}BASH_LIBS${RED}' ist nicht gesetzt!${RESET}"; \
		echo ""; \
		exit 1; \
	fi

# ─── Hilfe ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Alle verfügbaren Befehle anzeigen
	@echo
	@echo "Please use \`make <$(THEME_COLOR_GROUP)target$(RESET)>' where <target> is one of"
	@echo
	@echo "Project: $(THEME_COLOR_GROUP)$(PROJECT_NAME)$(RESET)"
	@echo
	@grep -hE '^(##@|[a-zA-Z0-9_-]+:.*?##[RD]? )' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*##[RD]? "}; \
	    /^##@/ { printf "\n$(THEME_INDENT_GROUP)$(THEME_COLOR_GROUP)%s$(RESET)\n", substr($$0, 4); next }; \
	    /##D /  { printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_DANGER)%-22s $(THEME_COLOR_DESC)%s$(RESET)\n", $$1, $$2; next }; \
	    /##R /  { printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_SERVER)%-22s $(THEME_COLOR_DESC)%s$(RESET)\n", $$1, $$2; next }; \
	    /## /   { printf "$(THEME_INDENT_TARGET)$(THEME_COLOR_TARGET)%-22s $(THEME_COLOR_DESC)%s$(RESET)\n", $$1, $$2 }'
	@echo

# ─── Info ────────────────────────────────────────────────────────────────────

.PHONY: info
info: ## Umgebungsvariablen anzeigen
	@echo
	@echo "    ${YELLOW}PROJECT_NAME${RESET}  = ${BLUE}$(PROJECT_NAME)${RESET}"
	@echo "    ${YELLOW}WORKSPACE${RESET}     = ${BLUE}$(WORKSPACE)${RESET}"
	@echo "    ${YELLOW}DEV_MAKE${RESET}      = ${BLUE}$${DEV_MAKE}${RESET}"
	@echo "    ${YELLOW}BASH_LIBS${RESET}     = ${BLUE}$${BASH_LIBS}${RESET}"
	@echo

# ─── Hints ───────────────────────────────────────────────────────────────────

.PHONY: hints
hints: ## Nützliche Links und Hinweise anzeigen
	@echo
	@echo "  ${YELLOW}GitHub${RESET}"
	@echo
	@printf "    ${BLUE}%-14s${RESET} ${WHITE}%s${RESET}\n" "Repo" "https://github.com/..."
	@echo

##@ Entwicklung

# Targets hier ergänzen ...

##@ Versionierung

.PHONY: version
version: ## Aktuelle Version anzeigen
	@echo
	@VER=$$(cat VERSION 2>/dev/null); \
	 [[ -z "$$VER" ]] && VER='nicht gesetzt'; \
	 TAG=$$(git describe --tags --abbrev=0 2>/dev/null || echo 'kein Tag'); \
	 echo "    ${YELLOW}VERSION${RESET}  = ${BLUE}$$VER${RESET}"; \
	 echo "    ${YELLOW}git tag${RESET}  = ${BLUE}$$TAG${RESET}"
	@echo

.PHONY: tags
tags: ## Letzte 10 Tags anzeigen
	@echo
	@git tag --sort=-version:refname -n1 | head -10 | \
	  awk '{printf "    \033[34m%-28s\033[0m \033[32m%s\033[0m\n", $$1, substr($$0, index($$0,$$2))}'
	@echo

.PHONY: tag-major
tag-major: precheck ## Version hochzählen — Major (X.y.z → X+1.0.0)  [MSG="..."]
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump major auto "" "$${MSG:-}"

.PHONY: tag-minor
tag-minor: precheck ## Version hochzählen — Minor (x.Y.z → x.Y+1.0)  [MSG="..."]
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump minor auto "" "$${MSG:-}"

.PHONY: tag-patch
tag-patch: precheck ## Version hochzählen — Patch (x.y.Z → x.y.Z+1)  [MSG="..."]
	source "$${BASH_LIBS}/version.lib.sh" && semVerBump patch auto "" "$${MSG:-}"
