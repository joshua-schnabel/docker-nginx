FROM alpine:3.10

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
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
      Description="Lightweight Nginx container."
	  
ENV DISABLETLS="false"

# Update packages and install packages 
RUN apk update && apk upgrade && \
    apk --no-cache add bash curl openssl coreutils && \
    apk --no-cache add nginx nginx-mod-http-headers-more && \
	apk --no-cache add logrotate && \
	rm -rf /var/cache/apk/*

# Ensure www-data user exists
# 82 is the standard uid/gid for "www-data" in Alpine
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

COPY ./CHANGELOG /CHANGELOG
COPY ./nginx /etc/nginx/
COPY ./media /media/
COPY ./logrotate.conf /etc/logrotate.d/nginx

# Setup folders
RUN mkdir -p /media/data && \
    mkdir -p /media/data/certs && \
    mkdir -p /media/data/dhparams && \
    mkdir -p /media/data/logs && \    
    mkdir -p /media/data/sites-enabled && \
    chown -R www-data:www-data /media/data && \
    touch /var/log/messages

COPY entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/media/data/logs","/media/data/certs","/media/data/dhparams","/media/data/webroot","/media/data/sites-enabled"]

HEALTHCHECK CMD curl -f http://localhost:4444/health || exit 1;

STOPSIGNAL SIGTERM

ENTRYPOINT ["entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
