#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Generate Docker-Image
#------------------------------------------------------------------------------

# Vars die in .bashrc gesetzt sein müssen. ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if [[ -z ${DEV_DOCKER+x} ]]; then echo "Var 'DEV_DOCKER' nicht gesetzt!"; exit 1; fi
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Abbruch bei Problemen (https://goo.gl/hEEJCj)
#
# Wenn ein Fehler nicht automatisch zu einem exit führen soll dann
# kann 'command || true' verwendet werden
#
# Für die $1, $2 Abfragen kann 'CMDLINE=${1:-}' verwendet werden
#
# -e Any subsequent(*) commands which fail will cause the shell script to exit immediately
# -o pipefail sets the exit code of a pipeline to that of the rightmost command
# -u treat unset variables as an error and exit
# -x print each command before executing it
set -eou pipefail

readonly APPNAME="$(basename "$0")"

readonly SCRIPT=$(realpath "$0")
readonly SCRIPTPATH=$(dirname "$SCRIPT")

#------------------------------------------------------------------------------
# Set WORKSPACE
#
cd "${SCRIPTPATH}"

mkdir -p logs
LOGFILE="logs/build-`date +%y%m%d`.log"

# shellcheck disable=SC2155
readonly DOCKER_BASE_IMAGE=$(\grep "^FROM " < Dockerfile | sed "s/FROM //")

# readonly REPO_HOST="hub.docker.com"
readonly REPO_HOST="docker.io"
readonly NAMESPACE="mangolila"
readonly NAME="certbot"

# readonly DOCKER_REGISTRY_PATH="${REPO_HOST}/${NAMESPACE}/${NAME}"
readonly DOCKER_CONFIG="${HOME}/.docker"
readonly DOCKER_PW_FILE="${DOCKER_CONFIG}/dockerhub.sec"

# TAGFILE="TAG.properties"
# Die TAG-Variable wird weiter unten im 'Tag-Block' erzeugt

# Default PORT
readonly PORT="8080"

# Default HOST_NAME ist mobiad.int.mikemitterer.at
# Wenn der HOST_NAME übergeben wird kann auch nur "mobiad" übergeben werden
# mobiad wird nach mobiad.int.mikemitterer.at übersetzt
# HOST_NAME=${2:-mobiad.int.mikemitterer.at}
#if [[ "${HOST_NAME}" == "mobiad" ]]; then
#    HOST_NAME="mobiad.int.mikemitterer.at"
#fi

# KEYSTORE_PATH_LOCAL="${DEV_SEC}/${HOST_NAME}/etc"

# AMAZON_REPO_URI="936985261795.dkr.ecr.eu-west-1.amazonaws.com"

#------------------------------------------------------------------------------
# Einbinden der globalen Build-Lib
#   Hier sind z.B. Farben, generell globale VARs und Funktionen definiert
#

if [[ "${__BUILD_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/build.lib.sh"; fi
if [[ "${__DOCKER_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/docker.lib.sh"; fi
if [[ "${__VERSION_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/version.lib.sh"; fi
if [[ "${__NET_LIB__:=""}" == "" ]]; then . "${BASH_LIBS}/net.lib.sh"; fi

if [[ "${MACHINE}" == "Mac" ]]; then
    readonly PROJECT_NAME="certbot"
else
    readonly PROJECT_NAME="docker.certbot"
fi
readonly PROJECT_DIR="${DEV_DOCKER}/${PROJECT_NAME}"

# CMDLINE kann ab hier verwendet werden ---------------------------------------

readonly CMDLINE=${1:-}
readonly OPTION=${2:-""}

# DEV_LOCAL ist bei den Jenkins-Tests bzw. in Docker-Containern nicht gesetzt,
# IS_CI geht also auf "true"
readonly IS_CI="${DEV_LOCAL:-"true"}"
readonly HAS_DEV_LOCAL="[[ ${IS_CI} != 'true' ]]"

# Die möglichen Plattformen:
#   https://docs.docker.com/build/building/multi-platform/

# Array mit den möglichen Plattformen
#
# darwin/arm64 darwin/amd64 - wird nicht unterstützt
#       exporting to image:
#       ERROR: failed to solve: operating system is not supported
#
readonly PLATFORMS=("linux/arm64 linux/amd64")

if [[ "${ARCHITECTURE}" == "x86_64" ]]; then
    readonly DEFAULT_PLATFORM="linux/amd64"
elif [[ "${ARCHITECTURE}" == "arm64" ]]; then
    readonly DEFAULT_PLATFORM="linux/arm64"
else
    # readonly DEFAULT_PLATFORM="darwin/arm64"
    readonly DEFAULT_PLATFORM="linux/arm64"
fi

# Check Commandline-Options

# Usage:
#   [[ ${IS_DRY_DRUN} == true ]] && debug "'${CMDLINE}' wants a 'dry-Run'"
# IS_DRY_DRUN=false

PLATFORM="${DEFAULT_PLATFORM}"
BUILD_MULTIARCH=false
while [ $# -ne 0 ]; do
    case "${1}" in
        --build | -b)
            shift
            if [[ "${OPTION}" == "x86" ]]; then
                PLATFORM=("linux/amd64")
            elif [[ "${OPTION}" == "arm" || "${OPTION}" == "m1" ]]; then
                PLATFORM=("linux/arm64")
            elif [[ "${OPTION}" == "all" ]]; then
                PLATFORM=("linux/arm64,linux/amd64")
                BUILD_MULTIARCH=true
            else
                PLATFORM=("${DEFAULT_PLATFORM}")
                echo "Platform: ${PLATFORM}"
                break
            fi
            #debug "'INFO_COMMAND' triggered with '${IS_INFO_COMMAND}'"
        ;;
    esac
    shift
done

#------------------------------------------------------------------------------
# Bei den Docker-Images ersetzt die hasVer-Version die
# Version-Tag-Variante
#

# Am [2024 09 17] wieder auf die "normale" Versionierung umgestellt
# TAG="$(hashVer 4 "" .)"

# git tag -a vx.x -m "description"
# TAG="$(gitMajorVersion).$(gitMinorVersion)"
TAG="$(hashVer 4 "" .)"

#------------------------------------------------------------------------------
# Functions
#

prepareConfig() {
    local _ULBIN="config/usr/local/bin"
    local _ULLIB="config/usr/local/lib/bash"

    mkdir -p config/root

    rm -rf "${_ULBIN}"; mkdir -p "${_ULBIN}"
    rm -rf "${_ULLIB}"; mkdir -p "${_ULLIB}"

    cp -a "${DEV_DOCKER}/_global/config/root/.bashrc" "config/root/"
    cp -a "${DEV_DOCKER}/_global/config/root/.config" "config/root/"
    cp -a "${DEV_DOCKER}/_global/config/root/.local" "config/root/"

    cp -a "${BASH_TOOLS}/genCerts.sh" "${_ULBIN}/"
    cp -a "${BASH_LIBS}/"*.* "${_ULLIB}/"

    cp -a "${PROJECT_DIR}"/cmds/docker-*.* "${_ULBIN}/"

  	# Run docker-choose.sh on interactive Docker!!! shells
  	# but not in ssh-sessions
 	  {
      echo
      echo
      echo "# Run docker-choose.sh on interactive shells"
      echo 'export BASH_LIBS="${BASH_LIBS:-/usr/local/lib/bash}"'
      echo 'if [[ -z ${SSH_TTY+x} ]]; then'
      echo "    docker-choose.sh"
      echo 'fi'
 	  } >> "config/root/.bashrc"
}

buildSingleArch() {
    docker build --platform "${PLATFORM}"  \
        -t "${NAMESPACE}/${NAME}:latest" -t "${NAMESPACE}/${NAME}:${TAG}" . | tee "${LOGFILE}" || exit 1

    local _ARCH=$(docker inspect "${NAMESPACE}/${NAME}:latest" --format "{{ .Architecture }}")
    echo -e "\n${GREEN}${NAMESPACE}/${NAME}:latest${NC} was built for ${YELLOW}${_ARCH}${NC}"

    showImages "${TAG}" ${NAMESPACE} ${NAME}
}

buildMultiArch() {
    loginToDockerHub

    echo -e "\nBuilder:\n${YELLOW}$(docker buildx inspect multiarch | sed 's/^/    /g')${NC}\n"

    # Das Image wird für die Plattformen ${PLATFORM} gebaut und gepusht
    docker buildx build --push --builder multiarch --platform "${PLATFORM}" \
        -t "${NAMESPACE}/${NAME}:latest" -t "${NAMESPACE}/${NAME}:${TAG}" . | tee "${LOGFILE}" || exit 1

    # Show Images funktioniert nicht mit buildx
    # Es wird die WebSite auf DockerHub geöffnet
    open https://hub.docker.com/repository/docker/mikemitterer/jenkins-master/tags
    # showImages "${TAG}" ${NAMESPACE} ${NAME}
}

build() {
    prepareConfig

    echo -e "\nBuilding for Platform: ${YELLOW}${PLATFORM}${NC}\n"

    if [[ "${BUILD_MULTIARCH}" == false ]]; then
        buildSingleArch
    else
        buildMultiArch
    fi

#    docker build -t "${NAMESPACE}/${NAME}:latest" . | tee ${LOGFILE} || exit 1
#    ID=$(docker images -q "${NAMESPACE}/${NAME}:latest")
#
#    docker tag "${ID}" "${NAMESPACE}/${NAME}:${TAG}"
#
#
#    # Amazon
#    docker tag "${NAMESPACE}/${NAME}:latest" "${AMAZON_REPO_URI}/${NAME}:latest"
#    docker tag "${NAMESPACE}/${NAME}:${TAG}" "${AMAZON_REPO_URI}/${NAME}:${TAG}"
#
#    showImages ${TAG} ${NAMESPACE} ${NAME} ${AMAZON_REPO_URI}
}




# Samples Array
# Die erste Zeile wird gesondert behandelt: (Sample-Beschreibung"
#   '#' - Wird durch den Index des Samples ersetzt
#   ||  - Markiert das Ende der ersten Zeile
#

declare -a samples=(
# Abfrage über die lokale IP-Adresse
# \t         -e FETCH_PUB_KEY_FROM_HOST=\"http://$(getIntIP):8080/id_rsa.pub\" \\
#

# Abfrage über Host-Name. Funktioniert allerdings aus Docker-Containern heraus nicht
# \t         -e FETCH_PUB_KEY_FROM_HOST=\"http://MacBook-Pro-M1.local:8080/id_rsa.pub\" \\

"# Execute bash ||
\t     docker run --name ${NAME} \\
\t         --rm -ti \\
\t         -v \${DEV_SHARED}:/data/shared \\
\t         -v ./data/letsencrypt:/etc/letsencrypt \\
\t         -v ./data/hetzner/hetzner.ini:/root/.hetzner.ini \\
\t         -v ./data/hetzner/prep4hetzner.sh:/start.d/03-prep_additional_hoster.sh \\
\t         ${NAMESPACE}/${NAME} \\
\t         bash
"

"# Execute bash with TZ set ||
\t     docker run --name ${NAME} \\
\t         --rm -ti \\
\t         -p 2020:22 \\
\t         -e TZ=\"Europe/Vienna\" \\
\t         -e LANG=\"de_DE.UTF-8\" \\
\t         -e LANGUAGE=\"de_DE:de\" \\
\t         -e LC_ALL=\"de_AT.UTF-8\" \\
\t         -e FETCH_PUB_KEY_FROM_HOST=\"http://$(getIntIP):8080/id_rsa.pub\" \\
\t         -v \${DEV_SHARED}:/data/shared \\
\t         -v ./data/letsencrypt:/etc/letsencrypt \\
\t         ${NAMESPACE}/${NAME} \\
\t         bash
"

"# Execute genCerts to generate zipped-Certs ||
\t     docker run --name ${NAME} \\
\t         --rm -ti \\
\t         -v \${DEV_SHARED}:/data/shared \\
\t         -v ./data/letsencrypt:/etc/letsencrypt \\
\t         ${NAMESPACE}/${NAME} \\
\t         --gen-certs
"
)


#------------------------------------------------------------------------------
# Options
#

usage() {
    echo
    echo -e "OS:           ${YELLOW}${MACHINE}${NC}"
    echo -e "Architecture: ${YELLOW}${ARCHITECTURE}${NC}"
    echo -e "Platform:     ${YELLOW}${PLATFORM}${NC}"
    echo
    echo "Usage: $(basename "$0") [ options ]"
    usageLine "-u | --update                          " "Update base image: ${YELLOW}${DOCKER_BASE_IMAGE}${NC}"
    echo
    usageLine "--prep                                 " "Prepare build-Environment (prepareConfig)"
    echo
    usageLine "-b | --build [ ${YELLOW}platform${NC} ]" "Build docker image: ${BLUE}${NAMESPACE}/${NAME}:${TAG}${NC}" 14
    usageLine "                                       " "'all' pushes the image to ${YELLOW}${REPO_HOST}/${NAMESPACE}/${NAME}${NC}"
    echo
    usageLine "                                         "    "${YELLOW}$PLATFORMS${NC}" 2
    usageLine "                                         "    "${YELLOW}x86${NC}      - shortcut for ${YELLOW}linux/amd64${NC}" 2
    usageLine "                                         "    "${YELLOW}arm | m1${NC} - shortcut for ${YELLOW}linux/arm64${NC}" 2
    usageLine "                                         "    "${YELLOW}all${NC}      - shortcut for ${YELLOW}linux/amd64, linux/arm64${NC}" 2
    echo
    usageLine "-p | --push                              " "Pushes the image to ${YELLOW}${REPO_HOST}/${NAMESPACE}/${NAME}${NC}"
    usageLine "-i | --images                            " "Show images for ${YELLOW}${NAMESPACE}/${NAME}${NC}"
    usageLine "-s | --samples [host | 'mobiad']         " "Show samples"
    echo
}


case "${CMDLINE}" in

    -u|--update)
        docker pull ${DOCKER_BASE_IMAGE}
    ;;

    --prep)
        prepareConfig
    ;;

    -b|--build)
        build
    ;;

    -i|--images)
        showImages ${TAG} ${NAMESPACE} ${NAME} "${REPO_HOST}/${NAMESPACE}"
    ;;

    -s|--samples)
        showSamples
    ;;

    -p|--push)
        pushImage2DockerHub ${NAMESPACE} ${NAME} "${TAG}"
    ;;

    help|-help|--help|*)
        usage
    ;;

esac

#------------------------------------------------------------------------------
# Alles OK...

exit 0
