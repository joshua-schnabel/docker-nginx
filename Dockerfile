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

ENV DISABLETLS="false"

# Install dos2unix first to fix line endings
RUN apk add --no-cache dos2unix

COPY ./CHANGELOG /CHANGELOG
COPY ./nginx /etc/nginx/
COPY ./application /application/
COPY ./logrotate/logrotate.conf /etc/logrotate.d/nginx

# Ensure www-data user exists und Rechte setzen
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data ; \
    mkdir -p /var/lib/nginx ; \
    chown -R www-data:www-data /var/lib/nginx/ && chmod -R 770 /var/lib/nginx/

# Update packages, install nur benötigte Pakete, acme.sh und bereinigen
RUN apk update && apk upgrade && \
    apk --no-cache add bash curl openssl nginx nginx-mod-http-lua nginx-mod-http-headers-more nginx-mod-stream nginx-mod-mail nginx-mod-http-dav-ext logrotate dos2unix && \
    rm -rf /var/cache/apk/* && \
    # Fix line endings and set permissions
    find /application -type f -name "*.sh" -exec dos2unix {} \; && \
    find /application -type f -name "*.sh" -exec chmod +x {} \; && \
    # Setup folders, Rechte 
    mkdir -p /application/data && \
    mkdir -p /application/data/lua && \
    mkdir -p /application/data/certs && \
    mkdir -p /application/data/dhparams && \
    mkdir -p /application/data/logs && \
    mkdir -p /application/data/sites-enabled && \
    mkdir -p /application/data/streams && \
    chown -R www-data:www-data /application/data && \
    # Setup Logrotate
    touch /var/log/messages && \
    chmod 644 /etc/logrotate.d/nginx && \
    chmod -R 777 /application/data/lua/ && \
    apk del dos2unix && \
    curl https://get.acme.sh | sh -s && \
    rm -rf /tmp/* /usr/share/doc /usr/share/man && \
    dos2unix /application/entrypoint.sh && \
    chmod +x /application/entrypoint.sh

VOLUME ["/application/data/logs","/application/data/certs","/application/data/dhparams","/application/data/webroot","/application/data/sites-enabled","/application/data/streams"]

HEALTHCHECK CMD curl -f http://localhost:4444/health || exit 1;

STOPSIGNAL SIGTERM

ENTRYPOINT ["/application/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
