#------------------------------------------------------------------------------
# Dockerimage:
#   mikemitterer/certbot
#
# Repository: https://hub.docker.com/repository/docker/mikemitterer/certbot/general
#
# Basis: https://hub.docker.com/_/debian
#
# Pull:
#   docker pull mikemitterer/certbot
#
#------------------------------------------------------------------------------

FROM debian:bookworm-slim

LABEL org.opencontainers.image.authors="Mike Mitterer <office@mikemitterer.at>"

# Set the env variable DEBIAN_FRONTEND to noninteractive
# Will be removed in start.sh!
# ENV DEBIAN_FRONTEND noninteractive

USER root

RUN DEBIAN_FRONTEND=noninteractive apt-get clean && apt-get -y update && apt-get install -y \
    apt-utils \
    dialog \
    mc \
    rsync \
    lsb-release \
    locales locales-all \
    gzip \
    unicode-data \
    screenfetch \
    wget \
    gnupg \
    libuptimed0 procps \
    iputils-ping \
    net-tools \
    moreutils \
    openjdk-17-jre-headless \
    curl \
    certbot \
    pandoc \
    openssh-server \
    jq \
    python3-pip \
    python3-venv \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Sollte das Problem der Fehlermeldung ganz am Anfang des Builds beheben
# Der Fehler wird durch ein abgelaufenes Zertifikat von nginx produziert
#RUN wget https://nginx.org/keys/nginx_signing.key -O - | apt-key add -

# - Set the locale + timezone --------------------------------------------------
#RUN echo "Europe/Vienna" > /etc/timezone && \
#    ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime && \
#    dpkg-reconfigure -f noninteractive tzdata && \
#    rm -f /usr/share/locale/locale.alias && \
#    ln -s /etc/locale.alias /usr/share/locale/locale.alias && \
#    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
#    sed -i -e 's/# de_AT.UTF-8 UTF-8/de_AT.UTF-8 UTF-8/' /etc/locale.gen && \
#    echo 'LANG="de_AT.UTF-8"'>/etc/default/locale && \
#    dpkg-reconfigure --frontend=noninteractive locales && \
#    update-locale LANG=de_AT.UTF-8 && \
#    echo "Europe/Vienna" > /etc/timezone

# Diese Vars können "im real life" in /etc/profile exportiert werden
#ENV TZ=Europe/Vienna
#ENV LANG=de_AT.UTF-8
#ENV LANGUAGE=de_AT.UTF-8
#ENV LC_ALL=de_AT.UTF-8

# - Volumes -------------------------------------------------------------------
ENV DEV_SHARED=/data/shared

# Über diesen Ordner tauschen der Jenkins-Client und der Docker-Container
# Daten aus
VOLUME ${DEV_SHARED}

# - Setup Bash ----------------------------------------------------------------
ENV TERM=xterm-256color

# Hier sind die BashTools + Libs zu finden
ENV BASH_TOOLS=/usr/local/bin
ENV BASH_LIBS=/usr/local/lib/bash

# Wird von einigen Tools benötigt
ENV LOG_HOME=/var/logs

COPY config/root/.bashrc /root/
COPY config/root/.config /root/.config
COPY config/root/.local /root/.local
COPY config/root/.local /root/.local

COPY config/usr/local/bin/* /usr/local/bin/
COPY config/usr/local/lib/bash/* /usr/local/lib/bash/

RUN chmod 500 /usr/local/bin/*

# Damit wird, wenn die Console aufgemacht wird, screenfetch nicht ausgeführt
ENV SHOW_SCREENFETCH=false

# - Setup Template-Folder ---------------------------------------------------------
# Templates werden mit start.d/cp-templates.sh in die
# entsprechenden /data/shared-Folder kopiert
ENV TEMPLATE_FOLDER=/data/templates

RUN mkdir -p "${TEMPLATE_FOLDER}/dist/certs"
COPY config${TEMPLATE_FOLDER}/dist/certs/README.md "${TEMPLATE_FOLDER}/dist/certs"

# - Setup Dist-Folder -------------------------------------------------------------
# Nur "dist" wird später mit nginx freigegeben
RUN mkdir -p "${DEV_SHARED}/dist"
RUN chown -R www-data:www-data ${DEV_SHARED}/dist

# - Ports ---------------------------------------------------------------------
# Default-Port für ssh-Server
# Kann z.B. mit -p 2222:22 gemappet werden
EXPOSE 22

# - INIT ----------------------------------------------------------------------
RUN mkdir -p /start.d
COPY config/start.d/* /start.d/

RUN chmod 550 /start.d
RUN chmod 550 /start.d/*.sh

COPY config/start.sh /
RUN chmod +x /start.sh

WORKDIR ${DEV_SHARED}

ENTRYPOINT [ "/start.sh" ]
CMD [ "--help" ]
