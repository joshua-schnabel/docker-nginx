FROM alpine:3.10
LABEL Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight container with Nginx."
	  
ENV IMAGE_VERSION="0.1.0-Beta"
ENV DISABLETLS="false"
ENV OPENSSL_CONF="/etc/nginx/openssl.conf"

# Update packages and install packages 
RUN apk update && apk upgrade && \
    apk --no-cache add bash curl openssl && \
    apk --no-cache add nginx nginx-mod-http-headers-more nginx-mod-http-lua

# Ensure www-data user exists
# 82 is the standard uid/gid for "www-data" in Alpine
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

ADD ./nginx.conf /etc/nginx/nginx.conf
ADD ./openssl.conf /etc/nginx/openssl.conf
ADD ./data /media/data
ADD ./defaults /media/defaults

# Setup folders
RUN mkdir -p /media/data && \
	mkdir -p /media/data/logs && \
	mkdir -p /media/data/sites-enabled && \
    mkdir -p /media/data/certs && \
    mkdir -p /media/data/dhparams

COPY entrypoint.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME /media/data/logs
VOLUME /media/data/certs
VOLUME /media/data/dhparams
VOLUME /media/data/webroot
VOLUME /media/data/sites-enabled

HEALTHCHECK CMD curl -f http://localhost:4444/health || exit 1;

STOPSIGNAL SIGTERM

ENTRYPOINT ["entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]