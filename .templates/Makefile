# Self-Documented Makefile see https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
#
# Basics zum Makefile:
#	https://makefiletutorial.com/#getting-started
#
# You can set these variables from the command line.
# BUILDDIR      = _build

# https://www.chiark.greenend.org.uk/doc/make-doc/make.html/Recipes.html#One-Shell
# .ONESHELL:

# Explizit setzt, denn unter Debian ist /bin/sh nicht gleich /bin/bash
# (per default ist /bin/sh ein symlink auf /bin/dash)
SHELL       := /bin/bash
# .SHELLFLAGS := -eu -o pipefail -c

.PHONY: help init update s2host info
# .PHONY: help init init312 build deploy

.DEFAULT_GOAL := help

# $(CURDIR) ist das aktuelle Verzeichnis und würde auch funktionieren
APPNAME := $(notdir $(firstword $(MAKEFILE_LIST)))
APPNAME_WITHOUT_EXTENSION := $(basename $(APPNAME))
APPNAME_LOWERCASE := $(shell echo "$(APPNAME_WITHOUT_EXTENSION)" | tr '[:upper:]' '[:lower:]')

WORKSPACE := $(realpath $(shell pwd))
PROJECT_NAME := $(notdir $(WORKSPACE))

CONFIG_DIR := .config
SCRIPTS_DIR := scripts

# Python
# init init312: ENVIRONMENT := ".vMLUtils"
# ENVIRONMENT   	:= ".vPetShopSample"

# Definiert in tests/unit/_resources/settings.toml
# UPLOAD_PATH     := "tests/unit/_resources/uploads"

include ${DEV_MAKE}/colours.mk
include ${DEV_MAKE}/tools.mk

# Kann in .env gesetzt bzw. überschrieben werden
SERVER_DIR := $(WORKSPACE)/website

-include .env
export

# Load .env file from server-dir
ifneq ($(wildcard ${SERVER_DIR}/.env),)
    include ${SERVER_DIR}/.env
    export
endif

SERVER_DIR_REL_PATH := ./$(patsubst $(WORKSPACE)/%,%,$(SERVER_DIR))
SNIPPETS_DIR := ${SERVER_DIR}/_wp/snippets

HOST_DIR := ${SERVER_DIR}/_host
HOST_ULO_DIR := ${HOST_DIR}/usr/local
HOST_ULO_BIN_DIR := ${HOST_ULO_DIR}/bin
HOST_ULO_LIB_DIR := ${HOST_ULO_DIR}/lib
HOST_ULO_LIB_MAKE_DIR := ${HOST_ULO_LIB_DIR}/make

REL_HOST_DIR := $(patsubst $(WORKSPACE)/%,%,$(HOST_DIR))

DATE_POSTFIX := $(shell date +%Y%m%d_%H%M)

help: precheck
	@echo
	@echo "Please use \`make <${YELLOW}target${RESET}>' where <target> is one of"
	@echo
	$(usageLine2) "help"               "This help message"
	$(usageLine2) "info"               "Zeigt wichtige Environment-Variablen"
	@echo
	$(usageLine2) "update"             "Aktualisiert externe Scripte und Libs. ($(WHITE)Keine CERTs!$(GREEN))"
	$(infoLine2)                           "Von BashLib, MakeLib usw zu $(YELLOW)$(REL_HOST_DIR)$(NC)"
	$(usageLine2) "lh2s | lh2server"   "Kopier die Files von $(HOST_DIR_REL_PATH) zum Server"
	$(usageLine2) "ios | instos"       "Installiert die Files aus $(HOST_DIR_REL_PATH) am Server"
	@echo
	@$(MAKE) hints

hints:
	@echo "${BLUE}Hints:${NC}"
	@echo "    Project         - ${YELLOW}${PROJECT_NAME}${RESET}"
	@echo "    Server-Dir      - ${YELLOW}${SERVER_DIR_REL_PATH}${RESET}"
	@echo

info: precheck
	@echo
	@echo "    ${YELLOW}PROJECT_NAME${RESET} =              ${BLUE}$(PROJECT_NAME)${RESET}"
	@echo "    ${YELLOW}WORKSPACE${RESET} =                 ${BLUE}$(WORKSPACE)${RESET}"
	@echo
	@echo "    ${YELLOW}SERVER_DIR_REL_PATH${RESET} =       ${BLUE}$(SERVER_DIR_REL_PATH)${RESET}"
	@echo
	@echo "    ${YELLOW}APPNAME${RESET} =                   ${BLUE}$(APPNAME)${RESET}"
	@echo "    ${YELLOW}APPNAME_WITHOUT_EXTENSION${RESET} = ${BLUE}$(APPNAME_WITHOUT_EXTENSION)${RESET}"
	@echo "    ${YELLOW}APPNAME_LOWERCASE${RESET} =         ${BLUE}$(APPNAME_LOWERCASE)${RESET}"
	@echo
	@echo "    ${YELLOW}CONFIG_DIR${RESET} =                ${BLUE}$(CONFIG_DIR)${RESET}"
	@echo "    ${YELLOW}SCRIPTS_DIR${RESET} =               ${BLUE}$(SCRIPTS_DIR)${RESET}"
	@echo

precheck:
	@if [ ! -d "$(SERVER_DIR_REL_PATH)" ]; then \
    	echo ""; \
		echo "${RED}Achtung: '${YELLOW}$(SERVER_DIR)${RED}' ist nicht vorhanden!${RESET}"; \
		echo ""; \
		exit 1; \
	fi
	@mkdir -p $(CONFIG_DIR)
	@mkdir -p $(SCRIPTS_DIR)

update: precheck
	@if [ ! -f ${HOST_ULO_DIR}/README.md ]; then \
		echo "# Scripts + Libs" > "${HOST_ULO_DIR}/README.md"; \
		echo "" >> "${HOST_ULO_DIR}/README.md"; \
		echo "Scripte und Libs werden mit dem Basis-Makefile (Project-Root)" >> "${HOST_ULO_DIR}/README.md"; \
		echo "synchronisiert bzw. updated." >> "${HOST_ULO_DIR}/README.md"; \
		echo "" >> "${HOST_ULO_DIR}/README.md"; \
		echo "\`install.sh\` wird durch "make update" generiert!" >> "${HOST_ULO_DIR}/README.md"; \
		echo "\`install.sh\` muss am Server richtig installiert + konfiguriert werden" >> "${HOST_ULO_DIR}/README.md"; \
		echo "\`local2Server -h\` zeigt die passenden Hints an!" >> "${HOST_ULO_DIR}/README.md"; \
	fi;

	@cp "${BASH_TOOLS}/unpackCert.sh" "${HOST_ULO_BIN_DIR}"
	@"${BASH_TOOLS}/local2Server.sh" -gi > "${HOST_ULO_BIN_DIR}/install.sh"
	@cp "${DEV_MAKE}/colours.mk" "${HOST_ULO_LIB_MAKE_DIR}"
	@cp "${DEV_MAKE}/tools.mk" "${HOST_ULO_LIB_MAKE_DIR}"

lh2server lh2s: precheck
	@# Aufrufe des Bash-Scrips
	@${BASH_TOOLS}/local2Server.sh --2host

instos ios: precheck
	@# Aufrufe des Bash-Scrips
	@${BASH_TOOLS}/local2Server.sh --install

