FROM alpine:3.10
LABEL Maintainer="Joshua Schnabel <dev@joshua-schnabel.de>" \
      Description="Lightweight container with Nginx."
	  
ENV DISABLETLS="false"

# Update packages and install packages 
RUN apk update && apk upgrade && \
    apk --no-cache add bash curl openssl coreutils && \
    apk --no-cache add nginx nginx-mod-http-headers-more && \
	apk --no-cache add logrotate

# Ensure www-data user exists
# 82 is the standard uid/gid for "www-data" in Alpine
RUN set -x ; \
    addgroup -g 82 -S www-data ; \
    adduser -u 82 -D -S -G www-data www-data && exit 0 ; exit 1

ADD ./CHANGELOG /CHANGELOG
ADD ./nginx.conf /etc/nginx/nginx.conf
ADD ./openssl.conf /etc/nginx/openssl.conf
ADD ./data /media/data
ADD ./defaults /media/defaults
ADD ./logrotate.conf /etc/logrotate.d/nginx

# Setup folders
RUN mkdir -p /media/data && \
    mkdir -p /media/data/certs && \
    mkdir -p /media/data/dhparams && \
    mkdir -p /media/data/logs && \    
    mkdir -p /media/data/sites-enabled && \
    chown -R www-data:www-data /media/data

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
