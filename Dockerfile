ARG ALPINEVERSION="3.22"

FROM alpine:$ALPINEVERSION
ARG ALPINEVERSION
ENV ALPINEVERSION=$ALPINEVERSION

ARG BUILD_DATE=""
ARG VCS_REF=""
ARG VERSION=""
ARG VENDORVERSION=""

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="jschnabel/nginx" \
      org.label-schema.description="Lightweight Nginx container" \
      org.label-schema.url="https://joshua-schnabel.de" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/joshua-schnabel/docker-nginx/" \
      org.label-schema.vendor="Joshua Schnabel" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0" \
      Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight Nginx container." \
	  alpine-version=${ALPINEVERSION} \
      nginx-version=$VENDORVERSION

# Statische Konfigurationen früher kopieren (ändern selten)
COPY --chown=root:root ./nginx /etc/nginx/
COPY --chown=root:root ./logrotate/logrotate-nginx.conf /etc/logrotate.d/nginx
COPY --chown=root:root ./logrotate/logrotate.conf /etc/logrotate.conf
COPY --chown=www-data:www-data --chmod=770 ./application /application/

EXPOSE 8080/tcp
EXPOSE 8443/tcp

HEALTHCHECK --interval=30s --timeout=2s --start-period=20s --retries=3 CMD wget -qO- http://127.0.0.1:4444/health >/dev/null || exit 1

STOPSIGNAL SIGTERM

WORKDIR /application

RUN set -eux; \
    apk --no-cache add \
      bash openssl curl \
      nginx nginx-mod-http-lua nginx-mod-http-headers-more nginx-mod-stream nginx-mod-mail nginx-mod-http-dav-ext \
      logrotate busybox-suid; \
    # Entferne vorhandene Gruppe/Benutzer und lege www-data neu an (UID/GID 1001), kein Login
    deluser www-data 2>/dev/null || true; \
    delgroup www-data 2>/dev/null || true; \
    addgroup -S -g 1001 www-data; \
    adduser -D -S -G www-data -u 1001 -h /application/data/certs/acmesh -s /bin/false www-data; \
    # App-Verzeichnisse (nur unter /application)
    mkdir -p /application/run /application/data/certs /application/data/logs /application/data/dhparams /application/data/sites-enabled /application/data/webroot /application/data/streams; \
    # Logdateien
    touch /application/data/logs/access.log /application/data/logs/error.log /application/data/logs/access.1.log /application/data/logs/error.1.log; \
    chown -R www-data:www-data /application; \
    chmod -R 770 /application/run; \
    \
    # Default-Nginx-Logpfad für sehr frühe Logs (vor dem Parsen von nginx.conf)
    mkdir -p /var/lib/nginx/logs; \
    touch /var/lib/nginx/logs/error.log; \
    chown -R www-data:www-data /var/lib/nginx; \
    chown -R www-data:www-data /var/lib/nginx/logs/error.log; \
    chmod -R 755 /var/lib/nginx; \
    \
    # Build- und Konvertierungs-Tools nur temporär
    apk --no-cache add --virtual .build-deps git dos2unix; \
    find /application -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \;; \
    find /application -type f -name ".gitkeep" -delete; \
    # logrotate Status unter /application/run halten
    mv /etc/crontabs/root /etc/crontabs/www-data; \
    # delete optional files
    rm /etc/logrotate.d/acpid; \
    rm /etc/logrotate.d/nginx.apk-new; \
    # Patch: add --skip-state-lock to daily logrotate invocation
    mkdir -p /application/run/logrotate; \
    touch /application/run/logrotate/logrotate.status; \
    chown -R www-data:www-data /application/run/logrotate; \
    chmod 770 /application/run/logrotate; \
    chmod 660 /application/run/logrotate/logrotate.status; \
    if [ -f /etc/periodic/daily/logrotate ]; then \
      # add flag only if not already present
      grep -q -- '--state /application/run/logrotate/logrotate.status' /etc/periodic/daily/logrotate || \
      sed -i 's#/usr/sbin/logrotate /etc/logrotate.conf#/usr/sbin/logrotate --state /application/run/logrotate/logrotate.status /etc/logrotate.conf#g' /etc/periodic/daily/logrotate; \
    fi; \
    dos2unix /application/entrypoint.sh; \
    chmod +x /application/entrypoint.sh; \
    # Cleanup    
    apk del dos2unix; \
    rm -rf /tmp/* /usr/share/doc /usr/share/man; \
    rm -rf /var/cache/apk/*; 

RUN set -eux; \
    # acme.sh installieren
    apk --no-cache add git; \
    cd /tmp; \
    git clone --depth 1 https://github.com/acmesh-official/acme.sh.git; \
    cd /tmp/acme.sh; \
    mkdir -p /application/data/certs/acmesh/config /application/data/certs/acmesh/certs; \
    ./acme.sh --install --home /application/bin/acmesh --config-home /application/data/certs/acmesh/config --cert-home /application/data/certs/acmesh/certs --ca-path /application/data/certs/acmesh/ca; \
    chown -R www-data:www-data /application/bin/; \
    chown -R www-data:www-data /application/data/certs/acmesh/; \
    rm -rf /tmp/* /usr/share/doc /usr/share/man; \
    rm -rf /var/cache/apk/*; \
    apk del git; \
    rm -rf /application/bin/acmesh/dnsapi /application/bin/acmesh/deploy /application/bin/acmesh/notify || true

# Sehr häufige Änderungen ganz am Ende (vermeidet Cache-Bust der schweren Layer)
COPY --chown=root:root ./CHANGELOG /CHANGELOG

VOLUME ["/application/data/"]

ENV HOME=/application/bin/acmesh
ENV LE_WORKING_DIR=/application/bin/acmesh
ENV TMPDIR=/application/tmp
USER www-data
ENTRYPOINT ["/application/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]