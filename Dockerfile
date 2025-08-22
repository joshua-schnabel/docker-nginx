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
COPY --chown=root:root ./logrotate/logrotate.conf /etc/logrotate.d/nginx

# App-Inhalte kopieren (ändern häufiger) und in einem Schritt vorbereiten
COPY --chown=www-data:www-data --chmod=770 ./application /application/

WORKDIR /application

# Pakete + User + Basisverzeichnisse in einem Layer
RUN set -eux; \
    apk --no-cache add bash openssl curl nginx nginx-mod-http-lua nginx-mod-http-headers-more nginx-mod-stream nginx-mod-mail nginx-mod-http-dav-ext logrotate; \
    # Gruppe/Benutzer idempotent anlegen (fallback ohne feste IDs, falls 82 bereits belegt)
    grep -q '^www-data:' /etc/group || addgroup -S -g 82 www-data || addgroup -S www-data; \
    id -u www-data >/dev/null 2>&1 || adduser -D -S -G www-data -u 82 www-data || adduser -D -S -G www-data www-data; \
    mkdir -p /var/lib/nginx /var/run/nginx /var/log/nginx; \
    # Logfiles
    touch /application/data/logs/access.log /application/data/logs/error.log /application/data/logs/access.1.log /application/data/logs/error.1.log; \
    chown -R www-data:www-data /var/lib/nginx /var/run/nginx /var/log/nginx /application; \
    chmod -R 770 /var/lib/nginx; 

RUN set -eux; \
    apk --no-cache add dos2unix; \
    # Shell-Skripte normalisieren + ausführbar machen
    find /application -type f -name "*.sh" -exec dos2unix {} \; -exec chmod +x {} \;; \
    # Placeholder-Dateien entfernen
    find /application -type f -name ".gitkeep" -delete; \
    \
    # Nginx Laufzeitdateien
    touch /var/run/nginx.pid; chown www-data:www-data /var/run/nginx.pid; \
    \
    # Logrotate/Permissions
    touch /var/log/messages 2>/dev/null || true; \
    chmod 644 /etc/logrotate.d/nginx; \
    chmod -R 755 /application/data/lua/; \
    \
    # entrypoint
    dos2unix /application/entrypoint.sh; \
    chmod +x /application/entrypoint.sh; \
    # Cleanup
    rm -rf /tmp/* /usr/share/doc /usr/share/man; \
    rm -rf /var/cache/apk/*; \
    apk del dos2unix; \
    rm -rf /application/bin/acmesh/dnsapi /application/bin/acmesh/deploy /application/bin/acmesh/notify || true

RUN set -eux; \
    # acme.sh installieren
    apk --no-cache add git; \
    cd /tmp; \
    git clone --depth 1 https://github.com/acmesh-official/acme.sh.git; \
    cd /tmp/acme.sh; \
    ./acme.sh --install --home /application/bin/acmesh --config-home /application/bin/acmesh/data --cert-home /application/bin/acmesh/certs; \
    chown -R www-data:www-data /application/bin/; \
    # Cleanup
    rm -rf /tmp/* /usr/share/doc /usr/share/man; \
    rm -rf /var/cache/apk/*; \
    apk del git; \
    rm -rf /application/bin/acmesh/dnsapi /application/bin/acmesh/deploy /application/bin/acmesh/notify || true

# Sehr häufige Änderungen ganz am Ende (vermeidet Cache-Bust der schweren Layer)
COPY --chown=root:root ./CHANGELOG /CHANGELOG

VOLUME ["/application/data/logs","/application/data/certs","/application/data/dhparams","/application/data/webroot","/application/data/sites-enabled","/application/data/streams"]

HEALTHCHECK --interval=30s --timeout=2s --start-period=20s --retries=3 CMD wget -qO- http://127.0.0.1:4444/health >/dev/null || exit 1

STOPSIGNAL SIGTERM

USER www-data

ENTRYPOINT ["/application/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]