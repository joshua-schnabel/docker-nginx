FROM alpine:3.10
LABEL Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight container with Nginx."
	  
ENV IMAGE_VERSION="0.1.0-Beta"
ENV DISABLETLS="false"

# Update packages and install packages 
RUN apk update && apk upgrade && \
    apk --no-cache add bash curl && \
    apk --no-cache add nginx nginx-mod-http-headers-more nginx-mod-http-lua

# Ensure www-data user exists
# 82 is the standard uid/gid for "www-data" in Alpine
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

# Setup folders
RUN mkdir -p /media/data/webroot && \
    mkdir -p /media/data/certs && \
    mkdir -p /media/data/dhparams && \
    mkdir -p /media/data/config
    
ADD ./nginx.conf /etc/nginx/nginx.conf
ADD ./config /media/data/config

COPY entrypoint.sh /usr/local/bin/

RUN chmod +x /startup.sh

VOLUME /media/data/certs
VOLUME /media/data/dhparams
VOLUME /media/data/webroot
VOLUME /media/data/config

HEALTHCHECK CMD curl -f http://localhost:4444/health || exit 1;

STOPSIGNAL SIGTERM

ENTRYPOINT ["entrypoint.sh"]
CMD ["nginx -g 'daemon off;'"]
